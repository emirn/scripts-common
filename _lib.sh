#!/bin/bash
# _lib.sh - Shared functions for scripts-common
# Source this file: source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

# Generate branch name from a description string
# Format: 2026-feb-24-164312-fix-bug-auth (stopwords filtered, up to 6 words)
# Usage: BRANCH=$(generate_branch_name "fix the auth bug in login")
generate_branch_name() {
    local msg="$1"

    # Stopwords to filter out (common filler words)
    local stopwords="for with to in on at as is the a an and or but"

    # Date: 2026-feb-24-164312
    local datestamp=$(date +%Y-)$(date +%b | tr '[:upper:]' '[:lower:]')$(date +-%d-%H%M%S)

    # Clean message: keep only alphanumeric, spaces, and dashes, convert to lowercase
    # Then normalize dashes to spaces so awk splits on both
    local clean_msg=$(echo "$msg" | tr -cd 'a-zA-Z0-9 -' | tr '[:upper:]' '[:lower:]' | tr '-' ' ')

    # Filter out stopwords and get first 6 meaningful words, rejoin with dashes
    local words=$(echo "$clean_msg" | awk -v stops="$stopwords" '
        BEGIN {
            n = split(stops, arr)
            for (i = 1; i <= n; i++) stopword[arr[i]] = 1
        }
        {
            count = 0
            result = ""
            for (i = 1; i <= NF && count < 6; i++) {
                if (!($i in stopword)) {
                    result = (result == "" ? $i : result "-" $i)
                    count++
                }
            }
            print result
        }
    ')

    # Fallback if empty
    [ -z "$words" ] && words="update"

    # Cap total length at 80 chars, truncating at a dash boundary
    local full="${datestamp}-${words}"
    if [ ${#full} -gt 80 ]; then
        full="${full:0:80}"
        # Trim to last dash boundary to avoid cutting mid-word
        full="${full%-*}"
    fi

    echo "$full"
}

# Extract first N meaningful words from a description (for short directory names)
# Usage: SHORT=$(short_name "fix the auth bug in login validation" 3)
short_name() {
    local msg="$1"
    local max_words="${2:-3}"
    local stopwords="for with to in on at as is the a an and or but"

    local clean_msg=$(echo "$msg" | tr -cd 'a-zA-Z0-9 -' | tr '[:upper:]' '[:lower:]' | tr '-' ' ')

    echo "$clean_msg" | awk -v stops="$stopwords" -v max="$max_words" '
        BEGIN {
            n = split(stops, arr)
            for (i = 1; i <= n; i++) stopword[arr[i]] = 1
        }
        {
            count = 0
            result = ""
            for (i = 1; i <= NF && count < max; i++) {
                if (!($i in stopword)) {
                    result = (result == "" ? $i : result "-" $i)
                    count++
                }
            }
            print result
        }
    '
}
