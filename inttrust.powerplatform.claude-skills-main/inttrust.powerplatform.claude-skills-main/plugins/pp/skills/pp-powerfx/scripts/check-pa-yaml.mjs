#!/usr/bin/env node
// check-pa-yaml.mjs - offline sanity checks for Power Apps canvas .pa.yaml sources.
// Zero dependencies. This is NOT a Power Fx compiler: it catches structural and
// name-resolution mistakes, not type errors or delegation warnings. Studio's App
// checker remains the authority (skill pp-powerfx).
//
// usage: node check-pa-yaml.mjs <SrcDir> [--known <file>] [--strict] [--only Employees.pa.yaml] [--update-baseline]
//   --known   the app's list of legitimately unresolvable names (data sources, tables, UDF parameters);
//             per project: tests.pa_yaml_known_unresolved in .claude/pp-project.yaml
//   --strict  treat warnings as failures (exit 1)
//   --update-baseline  rewrite the --known file from the current tree (only on a known-good tree)

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const optValue = name => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
const valueIdx = new Set(['--only', '--known'].map(o => argv.indexOf(o)).filter(i => i >= 0).map(i => i + 1));
const srcDir = argv.find((a, i) => !a.startsWith('--') && !valueIdx.has(i));
const knownFile = optValue('--known');
const strict = argv.includes('--strict');
const onlyIdx = argv.indexOf('--only');
const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : null;
const updateBaseline = argv.includes('--update-baseline');

if (!srcDir || !existsSync(srcDir)) {
  console.error('usage: node check-pa-yaml.mjs <SrcDir> [--known <file>] [--strict] [--only <file>] [--update-baseline]');
  process.exit(2);
}
if (updateBaseline && !knownFile) {
  console.error('--update-baseline needs --known <file>');
  process.exit(2);
}

// Power Fx built-in enum / signal namespaces that legitimately appear as Name.Member.
const ALLOWED_NAMESPACES = new Set([
  'Self', 'Parent', 'ThisItem', 'ThisRecord', 'App', 'Host', 'Compass', 'Connection',
  'Location', 'Acceleration', 'Param', 'User', 'Language',
  'Color', 'Font', 'FontWeight', 'Align', 'VerticalAlign', 'TextPosition', 'TextMode',
  'TextFormat', 'DisplayMode', 'BorderStyle', 'Overflow', 'ImagePosition', 'Transition',
  'ScreenTransition', 'DropShadow', 'Layout', 'LayoutDirection', 'LayoutAlignItems',
  'LayoutJustifyContent', 'LayoutOverflow', 'AlignInContainer', 'ScreenSize', 'Icon',
  'NotificationType', 'ErrorKind', 'ErrorState', 'DateTimeFormat', 'TimeUnit',
  'MatchOptions', 'Match', 'SortOrder', 'JSONFormat', 'PenMode', 'SelectedState',
  'Direction', 'MapStyle', 'GridStyle', 'Zoom', 'Theme', 'FormMode', 'FormPattern',
  'LoadingSpinner', 'Clock', 'MarkdownFlavor', 'TraceSeverity', 'ExternalMessage',
  'PDFPasswordState', 'BarcodeType', 'Appearance', 'TextRole', 'TextSize', 'Size',
  'FirstError', 'AllErrors', 'Errors', 'Blank', 'Table', 'Value', 'Text', 'DateAdd',
  'RequestHide', 'Weight', 'Style', 'ImageRotation', 'RemoveFlags', 'ShowLabels',
  // modern (Fluent) control enums
  'ButtonCanvas', 'ButtonAppearance', 'ButtonLayout', 'TextCanvas', 'IconStyle',
  'Spinner', 'SpinnerSize', 'TabListLayout', 'CheckboxCanvas', 'RadioSelectionType',
  'SearchBoxCanvas', 'DatePickerCanvas', 'ComboboxCanvas', 'DropdownCanvas',
  'ListboxCanvas', 'TextInputCanvas', 'TextInputMode', 'ProgressBar', 'Rating',
  'Slider', 'TabList', 'Accordion', 'Badge', 'Avatar', 'InfoButton', 'Divider',
  'TeachingBubble', 'ContainerLayout', 'ImageCanvas', 'MediaCanvas', 'Markdown',
  'TableStyle', 'FluentTheme', 'ChartLegend', 'ChartType', 'GridLine',
  // misc built-ins
  'TraceOptions', 'LaunchTarget', 'StartOfWeek', 'SortByColumns', 'Toggle',
]);

// Names that are unresolvable from .pa.yaml alone but are legitimate: connector
// and cloud-flow data sources, plus Dataverse/SQL table names. These live in the
// solution manifest, not in the screen YAML. The list is per app (--known).
const BASELINE_FILE = knownFile;
let baseline = new Set();
if (!BASELINE_FILE && !updateBaseline) console.log('note: no --known list given - data sources and tables will be reported as unresolved');
if (BASELINE_FILE) try {
  baseline = new Set(
    readFileSync(BASELINE_FILE, 'utf8')
      .split(/\r?\n/)
      .map(l => l.replace(/#.*$/, '').trim())
      .filter(Boolean)
  );
} catch { /* first run, no baseline yet */ }

const files = readdirSync(srcDir)
  .filter(f => f.endsWith('.pa.yaml') && f !== '_EditorState.pa.yaml')
  .map(f => ({ rel: f, abs: join(srcDir, f) }));

const compDir = join(srcDir, 'Components');
if (existsSync(compDir)) {
  for (const f of readdirSync(compDir).filter(f => f.endsWith('.pa.yaml'))) {
    files.push({ rel: 'Components/' + f, abs: join(compDir, f) });
  }
}

// ---------------------------------------------------------------- helpers

// Blank out Power Fx string literals and comments so bracket / identifier
// scanning does not trip over text content. Newlines are preserved so that
// reported line numbers stay accurate.
function stripLiterals(src) {
  let out = '';
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === '"') {
      out += ' ';
      i++;
      while (i < src.length) {
        if (src[i] === '"') {
          if (src[i + 1] === '"') { out += '  '; i += 2; continue; }
          break;
        }
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      out += ' ';
      continue;
    }
    if (c === '/' && src[i + 1] === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i++; }
      if (i < src.length) out += '\n';
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      i += 2; out += '  ';
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      i++; out += '  ';
      continue;
    }
    out += c;
  }
  return out;
}

// Split a file into structural lines plus block-scalar (multi-line formula) regions.
function parse(lines) {
  const structural = [];
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const m = line.match(/^(\s*)([A-Za-z_][A-Za-z0-9_ -]*):\s*[|>][-+]?\s*$/);
    if (m) {
      const indent = m[1].length;
      const body = [];
      const startLine = i + 2;
      let j = i + 1;
      while (j < lines.length) {
        const l = lines[j];
        if (l.trim() === '') { body.push(''); j++; continue; }
        const ind = l.match(/^(\s*)/)[1].length;
        if (ind <= indent) break;
        body.push(l);
        j++;
      }
      const nonEmpty = body.filter(l => l.trim() !== '');
      const baseIndent = nonEmpty.length
        ? Math.min(...nonEmpty.map(l => l.match(/^(\s*)/)[1].length))
        : indent + 2;
      blocks.push({ key: m[2], keyLine: i + 1, indent, baseIndent, body: body.join('\n'), startLine });
      structural.push({ n: i + 1, indent, text: line.trim() });
      i = j;
      continue;
    }
    structural.push({ n: i + 1, indent: line.match(/^(\s*)/)[1].length, text: line.trim() });
    i++;
  }
  return { structural, blocks };
}

function bracketReport(text, label, firstLine) {
  const clean = stripLiterals(text);
  const closeOf = { ')': '(', ']': '[', '}': '{' };
  const openOf = { '(': ')', '[': ']', '{': '}' };
  const stack = [];
  let line = firstLine;
  const errs = [];
  for (const ch of clean) {
    if (ch === '\n') { line++; continue; }
    if (openOf[ch]) stack.push({ ch, line });
    else if (closeOf[ch]) {
      const top = stack.pop();
      if (!top) errs.push(label + ': stray ' + ch + ' at line ' + line);
      else if (top.ch !== closeOf[ch]) {
        errs.push(label + ': ' + top.ch + ' opened at line ' + top.line + ' closed by ' + ch + ' at line ' + line);
      }
    }
  }
  for (const s of stack) errs.push(label + ': unclosed ' + s.ch + ' opened at line ' + s.line);
  return errs;
}

// ---------------------------------------------------------------- pass 1: declarations

const declared = new Map();
const duplicates = [];
const parsedFiles = [];

function declare(name, where) {
  if (declared.has(name)) duplicates.push({ name, first: declared.get(name), second: where });
  else declared.set(name, where);
}

for (const f of files) {
  const raw = readFileSync(f.abs, 'utf8');
  const lines = raw.split(/\r?\n/);
  const { structural, blocks } = parse(lines);
  parsedFiles.push({ ...f, raw, lines, structural, blocks });

  for (const s of structural) {
    let m;
    // screen or component definition sits at indent 2 under the top-level collection
    if (s.indent === 2 && (m = s.text.match(/^([A-Za-z_][A-Za-z0-9_]*):$/))) {
      declare(m[1], f.rel + ':' + s.n);
    }
    // control instance: "- Name:"
    if ((m = s.text.match(/^- ([A-Za-z_][A-Za-z0-9_]*):$/))) {
      declare(m[1], f.rel + ':' + s.n);
    }
  }

  // App-level named formulas: "Name = ..." statements inside the Formulas block
  for (const b of blocks) {
    if (b.key !== 'Formulas') continue;
    for (const l of b.body.split('\n')) {
      // Power Fx uses = for equality as well, so only a statement sitting at the
      // block's own base indent can be a named-formula declaration; an indented
      // `kind = "name"` is a comparison inside a larger expression.
      if (l.trim() === '') continue;
      if (l.match(/^(\s*)/)[1].length !== b.baseIndent) continue;
      const m = l.match(/^\s*=?([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/);
      if (m) declare(m[1], f.rel + ':' + b.keyLine);
    }
  }
}

// context and global variables, harvested across the whole app
const vars = new Set();
for (const pf of parsedFiles) {
  const all = stripLiterals(pf.raw);
  for (const m of all.matchAll(/\bSet\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)/g)) vars.add(m[1]);
  for (const m of all.matchAll(/\bUpdateContext\s*\(\s*\{([\s\S]{0,4000}?)\}\s*\)/g)) {
    for (const v of m[1].matchAll(/(?:^|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/g)) vars.add(v[1]);
  }
  for (const m of all.matchAll(/\bWith\s*\(\s*\{([\s\S]{0,2000}?)\}/g)) {
    for (const v of m[1].matchAll(/(?:^|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/g)) vars.add(v[1]);
  }
  // "ForAll(src As Day, ...)" introduces Day as a record-scope alias
  for (const m of all.matchAll(/\bAs\s+([A-Za-z_][A-Za-z0-9_]*)/g)) vars.add(m[1]);
  // "SomeFlow.Run(...)" names a cloud flow or connector, not a control
  for (const m of all.matchAll(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*Run\s*\(/g)) vars.add(m[1]);
}

// ---------------------------------------------------------------- pass 2: per-file checks

const errors = [];
const warns = [];
const allUnresolved = new Set();
const target = only
  ? parsedFiles.filter(p => p.rel === only || p.rel.endsWith('/' + only))
  : parsedFiles;

for (const pf of target) {
  const E = m => errors.push(pf.rel + ': ' + m);
  const W = m => warns.push(pf.rel + ': ' + m);

  // Power Apps re-emits this banner on every export; losing it means the file was
  // rewritten wholesale rather than edited, which the round-trip will reject.
  if (!pf.lines[0] || !pf.lines[0].startsWith('# *')) {
    E('line 1: missing the generated "# ****" header banner');
  }

  // Tabs are only illegal in YAML *indentation*. Power Apps itself emits
  // tab-indented continuation lines inside formula block scalars, where the tab
  // is content rather than structure.
  const blockLines = new Set();
  for (const b of pf.blocks) {
    const n = b.body === '' ? 0 : b.body.split('\n').length;
    for (let k = 0; k < n; k++) blockLines.add(b.startLine + k);
  }
  pf.lines.forEach((l, i) => {
    if (blockLines.has(i + 1)) return;
    if (/^ *\t/.test(l)) E('line ' + (i + 1) + ': TAB in YAML indentation');
  });

  for (const s of pf.structural) {
    if (s.text !== '' && s.indent % 2 !== 0) {
      E('line ' + s.n + ': indent ' + s.indent + ' is not a multiple of 2');
    }
  }

  // every value under a Properties: map must be a formula (=... or a |- block)
  let inProps = null;
  for (const s of pf.structural) {
    if (s.text === 'Properties:') { inProps = s.indent; continue; }
    if (inProps !== null && s.text !== '' && s.indent <= inProps) inProps = null;
    if (inProps === null || s.indent !== inProps + 2) continue;
    const m = s.text.match(/^([A-Za-z_][A-Za-z0-9_ -]*):\s*(.*)$/);
    if (!m) continue;
    const val = m[2].trim();
    if (val === '' || /^[|>][-+]?$/.test(val)) continue;   // block scalar follows
    if (!val.startsWith('=')) {
      E('line ' + s.n + ': property "' + m[1] + '" value does not start with = -> ' + val.slice(0, 60));
    }
  }

  for (const b of pf.blocks) {
    errors.push(...bracketReport(b.body, pf.rel + ': ' + b.key + ' (line ' + b.keyLine + ')', b.startLine));
  }
  for (const s of pf.structural) {
    const m = s.text.match(/^([A-Za-z_][A-Za-z0-9_ -]*):\s*(=.*)$/);
    if (m) errors.push(...bracketReport(m[2], pf.rel + ': ' + m[1] + ' (line ' + s.n + ')', s.n));
  }

  // identifier resolution: Name.Member where Name is declared nowhere
  const seenUnknown = new Map();
  const scanRefs = (text, line, label) => {
    const clean = stripLiterals(text);
    let ln = line;
    for (const part of clean.split('\n')) {
      for (const m of part.matchAll(/\b([A-Z][A-Za-z0-9_]*)\s*\./g)) {
        const name = m[1];
        if (declared.has(name) || ALLOWED_NAMESPACES.has(name) || vars.has(name)) continue;
        allUnresolved.add(name);
        if (baseline.has(name)) continue;
        if (!seenUnknown.has(name)) seenUnknown.set(name, label + ' line ' + ln);
      }
      ln++;
    }
  };
  for (const b of pf.blocks) scanRefs(b.body, b.startLine, b.key);
  for (const s of pf.structural) {
    const m = s.text.match(/^([A-Za-z_][A-Za-z0-9_ -]*):\s*(=.*)$/);
    if (m) scanRefs(m[2], s.n, m[1]);
  }
  for (const [name, where] of seenUnknown) {
    W('unresolved reference "' + name + '." (first seen at ' + where + ') - not a screen, control, component, named formula, variable, or known Power Fx namespace');
  }
}

for (const d of duplicates) {
  errors.push('duplicate name "' + d.name + '" declared at ' + d.first + ' and ' + d.second + ' (canvas app names must be globally unique)');
}

// ---------------------------------------------------------------- report

if (updateBaseline) {
  const header = [
    '# Names referenced by the app that cannot be resolved from .pa.yaml alone:',
    '# connector and cloud-flow data sources, Dataverse/SQL tables, and record',
    '# scope aliases. Anything NOT listed here is reported as an unresolved',
    '# reference. Regenerate against a known-good tree with --update-baseline.',
    '',
  ].join('\n');
  writeFileSync(BASELINE_FILE, header + [...allUnresolved].sort().join('\n') + '\n');
  console.log('baseline written: ' + allUnresolved.size + ' name(s) -> ' + BASELINE_FILE);
  process.exit(0);
}

console.log('checked: ' + target.map(t => t.rel).join(', '));
console.log('declared names: ' + declared.size + ', variables: ' + vars.size);
if (errors.length) {
  console.log('\nERRORS (' + errors.length + '):');
  for (const e of errors) console.log('  x ' + e);
}
if (warns.length) {
  console.log('\nWARNINGS (' + warns.length + '):');
  for (const w of warns) console.log('  ! ' + w);
}
if (!errors.length && !warns.length) console.log('\nclean');

process.exit(errors.length || (strict && warns.length) ? 1 : 0);
