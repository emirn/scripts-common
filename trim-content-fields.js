#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const DATA_ROOT = path.resolve(__dirname, '..', 'blogpostgen-data', 'data', 'projects');

const PROJECTS = [
  'aicw.io',
  'aidatabasetools.com',
  'ayodesk.com',
  'guruka.com',
  'legavima.com',
  'revdoku.com',
];

let totalFiles = 0;
let modifiedFiles = 0;

function findIndexJsonFiles(dir) {
  const results = [];
  if (!fs.existsSync(dir)) return results;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === '_history') continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findIndexJsonFiles(fullPath));
    } else if (entry.name === 'index.json') {
      results.push(fullPath);
    }
  }
  return results;
}

for (const project of PROJECTS) {
  const projectDir = path.join(DATA_ROOT, project);
  const dirs = ['drafts', 'pages'].map(d => path.join(projectDir, d));

  for (const dir of dirs) {
    const files = findIndexJsonFiles(dir);
    for (const filePath of files) {
      totalFiles++;
      const raw = fs.readFileSync(filePath, 'utf-8');
      const data = JSON.parse(raw);
      let changed = false;

      for (const key of Object.keys(data)) {
        if (typeof data[key] === 'string') {
          const trimmed = data[key].trim();
          if (trimmed !== data[key]) {
            data[key] = trimmed;
            changed = true;
          }
        }
      }

      if (changed) {
        modifiedFiles++;
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf-8');
        const rel = path.relative(DATA_ROOT, filePath);
        console.log(`  trimmed: ${rel}`);
      }
    }
  }
}

console.log(`\nDone. Scanned ${totalFiles} files, modified ${modifiedFiles}.`);
