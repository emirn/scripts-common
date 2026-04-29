#!/bin/bash
# _lib.sh - Shared functions for scripts-common
# Source this file: source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

branch_name_source_line() {
    local msg="$1"

    # Branch names should come from the first meaningful line only. Commit
    # bodies are often multiline bullet lists and file paths; using the whole
    # body makes noisy branch names and can join words across punctuation.
    printf '%s\n' "$msg" | awk '
        NF {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            sub(/^([-*]+|[0-9]+[.)])[[:space:]]+/, "", line)
            if (line !~ /[[:alnum:]]/) next
            print line
            exit
        }
    '
}

slug_words() {
    local msg="$1"
    local max_words="${2:-6}"

    # Stopwords to filter out (common filler words and file extensions that
    # commonly appear when commit messages mention specific paths).
    local stopwords="for with to in on at as is the a an and or but of from into via by until this that these those be been being are was were it its there their then now rb js ts tsx jsx py sh md yml yaml json html erb css scss"

    # Convert every non-alphanumeric run into a word boundary instead of
    # deleting punctuation. This keeps "OTP/email" as "otp email" instead of
    # the invalid-looking "otpemail".
    local clean_msg
    clean_msg=$(printf '%s' "$msg" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's#(^|[[:space:]])[^[:space:]]*/[^[:space:]]*/[^[:space:]]*# #g; s/[^[:alnum:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')

    printf '%s\n' "$clean_msg" | awk -v stops="$stopwords" -v max="$max_words" '
        BEGIN {
            n = split(stops, arr)
            for (i = 1; i <= n; i++) stopword[arr[i]] = 1
        }
        {
            count = 0
            result = ""
            for (i = 1; i <= NF && count < max; i++) {
                if (length($i) > 1 && !($i in stopword)) {
                    result = (result == "" ? $i : result "-" $i)
                    count++
                }
            }
            print result
        }
    '
}

# Generate branch name from a description string
# Format: 2026-feb-24-164312-fix-bug-auth (stopwords filtered, up to 6 words)
# Usage: BRANCH=$(generate_branch_name "fix the auth bug in login")
generate_branch_name() {
    local msg="$1"

    # Date: 2026-feb-24-164312
    local datestamp=$(date +%Y-)$(date +%b | tr '[:upper:]' '[:lower:]')$(date +-%d-%H%M%S)

    local summary
    summary=$(branch_name_source_line "$msg")

    local words
    words=$(slug_words "$summary" 6)

    # Fallback if empty
    [ -z "$words" ] && words="update"

    # Cap total length at 80 chars, truncating the slug at a dash boundary.
    local max_slug_len=$((80 - ${#datestamp} - 1))
    if [ "${#words}" -gt "$max_slug_len" ]; then
        words="${words:0:$max_slug_len}"
        # Trim to last dash boundary to avoid cutting mid-word
        words="${words%-*}"
        [ -z "$words" ] && words="update"
    fi

    echo "${datestamp}-${words}"
}

# Extract first N meaningful words from a description (for short directory names)
# Usage: SHORT=$(short_name "fix the auth bug in login validation" 3)
short_name() {
    local msg="$1"
    local max_words="${2:-3}"

    slug_words "$(branch_name_source_line "$msg")" "$max_words"
}
