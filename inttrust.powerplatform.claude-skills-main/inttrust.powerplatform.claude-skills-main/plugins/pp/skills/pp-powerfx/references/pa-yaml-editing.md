# Editing canvas .pa.yaml sources by hand

For apps kept as unpacked `Src/*.pa.yaml` in a Dataverse-git repo (config: `solution.canvas_apps[].src`). Ship the
edit with pp-release (`references/dataverse-git.md`).

## Scope the edit
- One file per screen (`<Screen>.pa.yaml`), app-wide formulas / OnStart / OnError in `App.pa.yaml`, components under
  `Components/`. Files run to 1,500+ lines of nested `Children:` - grep the control name and read enough context to know
  the indent depth before editing.
- If the change needs data the app does not fetch yet, it is a proc or flow change, not a YAML change (pp-sql, pp-flows).
- `.pa.yaml` is a preview format meant for review and small edits: keep edits surgical; large restructures belong in
  Studio. Never rewrite a whole file; keep the `# ****` banner. Never touch `_EditorState.pa.yaml` or `Controls/*.json`.

## Syntax rules
- Two-space indentation, spaces only, in the structure; inside a `|-` formula block keep the indentation Studio wrote
  (App.pa.yaml uses tabs there).
- Every property value is a formula: `Fill: =Color.White`, or `|-` then `=...`. A plain scalar must not contain `: `
  (colon-space) - use the `|-` block form, or the whole file stops being YAML.
- Control names are unique app-wide, not per screen.
- A bare name that collides with a control property needs the global operator: `FalseFill: =[@BorderColor]`.
- A property on the wrong node (for example `AccessibleLabel` beside `Properties:` instead of inside it) makes Studio
  refuse to open the app; no offline check catches it.
- Changing an existing control's `Variant` in YAML may not apply in place - rename the control so it is created fresh.
- A new component defined only in YAML (`Src/Components/<Name>.pa.yaml` + `CanvasComponent` instances) imports cleanly.
- Modern controls are recoloured with `BasePaletteColor` (the modern theme is not in git). Check the control supports a
  property before using it; the resolved property list per control type comes from the publish-time `Controls/*.json`
  (names only - they lag the YAML):

```bash
node -e '
const fs=require("fs"),path=require("path");const p=new Map();
for(const f of fs.readdirSync("Controls")){let j;try{j=JSON.parse(fs.readFileSync(path.join("Controls",f),"utf8"))}catch{continue}
(function w(n){if(!n)return;const t=n.Template||{},k=t.Name+"@"+t.Version;
if(!p.has(k))p.set(k,new Set());for(const r of(n.Rules||[]))p.get(k).add(r.Property);
for(const c of(n.Children||[]))w(c)})(j.TopParent)}
for(const[k,v]of[...p].sort())console.log("### "+k+"\n"+[...v].sort().join(" ")+"\n")'
```
  Run it from a `..._DocumentUri` folder. Known answers: `modernButton@1.0.0` supports `BasePaletteColor` and the four
  `Radius*` but has no `Fill`; `label@2.5.1` has `Wrap` but no corner radius; the modern `Toggle@1.1.5` has no colour
  property (use `Classic/Toggle@2.1.0`); the classic text input has `Clear`.

## Offline gates (both catch structure and names only)
1. `node "<pp-powerfx skill folder>/scripts/check-pa-yaml.mjs" <Src> --known <tests.pa_yaml_known_unresolved> --strict`
   (`--only <file>` narrows the report). A legitimate new data-source name, gallery column or UDF parameter name that
   is declared nowhere else goes into the project's known list with a comment - never disable the check.
2. `pac canvas validate --directory <..._DocumentUri>` with pac **2.3.2** (2.12.2 no longer supports it). Its schema
   lags, so every file reports "Invalid"; the signal is the diff of its output against the pristine tree (restore the
   files from `git show <base>:<path>` into a copy, strip the absolute path prefixes). `pac canvas pack` is deprecated
   and crashes on these apps.
3. Then App checker -> Formulas (0) in Studio after the pull - the only type checker.

Keep line endings (the working tree is CRLF): `git diff --stat` showing a whole file changed means they were
rewritten. Node, or Python reading and writing with `newline=''`, keeps them; `sed -i` rewrites the whole file to
LF. Match multi-line patterns on `\r\n`, not `\n`.
