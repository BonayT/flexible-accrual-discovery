// Bundles the simulator into a single self-contained file, for publishing where
// a page cannot fetch its siblings.
//
//   node bin/build_artifact.mjs > build/simulator.artifact.html
//
// The Pages copy stays modular and keeps fetching catalog.json; this is the same
// page with its imports resolved and its data inlined, so nothing is maintained
// twice.

import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL(`../docs/${p}`, import.meta.url), 'utf8');

// Turn a module into plain script: drop its imports, and turn its exports into
// declarations the concatenated scope already has.
const flatten = (source) =>
  source
    .replace(/^import[\s\S]*?from\s+'[^']+';\s*$/gm, '')
    .replace(/^export\s+\{[\s\S]*?\};\s*$/gm, '')
    .replace(/^export\s+(const|function|class)\s/gm, '$1 ');

const catalog = read('catalog.json');
const modules = ['cel.js', 'engine.js', 'walls.js', 'prompts.js', 'pains.js'].map(read).map(flatten);

const html = read('simulator.html');

const head = html.slice(html.indexOf('<title>'), html.indexOf('</style>') + 8);
const bodyStart = html.indexOf('<h1>');
const scriptStart = html.indexOf('<script type="module">');
const body = html.slice(bodyStart, scriptStart);

let script = html.slice(scriptStart + '<script type="module">'.length, html.lastIndexOf('</script>'));
script = script
  .replace(/^import[\s\S]*?from\s+'\.\/[^']+';\s*$/gm, '')
  .replace(/const catalog = await fetch\('\.\/catalog\.json'\)\.then\(\(r\) => r\.json\(\)\);/, `const catalog = ${catalog};`);

process.stdout.write(`${head}\n${body}\n<script type="module">\n${modules.join('\n')}\n${script}\n</script>\n`);
