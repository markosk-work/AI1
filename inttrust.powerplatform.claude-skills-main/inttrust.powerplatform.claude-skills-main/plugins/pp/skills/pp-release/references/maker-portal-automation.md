# Driving Studio, the maker portal and the player from a browser

Hard-won mechanics for Claude in Chrome (or any CDP-driven browser) on make.powerapps.com, Studio and the player.
Identities come from the local config (`browser_profiles`, `accounts`).

## Identity
- Several Chrome profiles can be connected at once; names ("Browser 1..n") and device ids churn - neither identifies a
  profile. Before any privileged click, verify the account from page evidence in that browser: the maker portal's
  account-manager button (name / avatar). `myaccount.microsoft.com` can mislead where device SSO signs every profile
  in as the Windows user.
- A first-run country / terms dialog on make.powerapps.com means the wrong account (one that never used the portal) -
  never accept it.
- With several profiles connected, the selected browser can reset after each call: select it again before each call,
  and if another profile keeps taking over, have the user quit that Chrome completely.
- Never type passwords; when a page asks to re-verify, leave the tab for the user.

## Visibility
- Clicks and screenshots only work while the window is actually on screen. A covered or minimised window reports
  `document.visibilityState === 'hidden'`: coordinate clicks are ignored and screenshots time out. Ask the user to
  place Chrome side by side before pane or Studio work.
- From a hidden tab, DOM clicks through the JS tool usually still work in the maker portal: find command-bar items by
  `[aria-label="Check for updates"]` (their innerText is empty when hidden), tabs by `[role=tab]`, toasts by
  `[role=alert],[role=status]`. The branch picker is a react-select: set its input with the native value setter plus an
  `input` event, then click the `[role=option]` whose text is exactly the branch.
- JS evaluations time out at about 45 s - keep in-page waits under 30 s. A Pull click can take over 30 s to show
  "Pull completed successfully".
- Pane Commit from a hidden tab: a JS `.click()` opens the Commit dialog; set the Comment textarea with the native
  `HTMLTextAreaElement` value setter plus an `input` event (Commit stays disabled until then; form filling leaves it
  empty); then click Commit. The toast reads `Commit completed successfully.<sha>`.
- The classifier may block some scripted clicks (Disconnect, Accept incoming, Commit, flow on/off, permission grants):
  a standalone click by ref or coordinates, or the user's explicit go, gets through. Don't retry blocked actions in a
  loop - ask.

## Studio
- The canvas and its panes are a cross-origin iframe: `read_page` / `find` see only the outer shell - drive it from
  screenshots and coordinates. Maker-portal pages (source control, flows) are not iframes - prefer `read_page` + refs
  there, and fall back to coordinates when ref clicks do nothing after a navigation.
- Keep exactly one Studio tab: a second tab steals the editing lock; a just-closed tab keeps it for a few minutes
  ("you already have editing control elsewhere" - Override is safe when it is yours). A backgrounded Studio preview
  pauses.
- Studio preview and App checker work in Read-only mode; only editing needs the lock.
- App checker: stethoscope icon in the top-right toolbar (in the right-hand rail when the window is narrow); open it and
  read **Formulas (n)** after "Recheck all".
- Studio dirties itself on open, so leaving raises "Leave site?". Defuse it by removing the iframes first
  (`document.querySelectorAll('iframe').forEach(f => f.remove())`), then navigate or close. Never save to get past it.
- Screenshots after a click that re-renders the canvas can time out for ~10 s: wait, capture once per batch, last. Do not
  use zoom in Studio: a failed zoom can leave the tab's viewport stuck (recover: remove iframes, close the tab, open a
  fresh one). Take a fresh screenshot before every coordinate click - toolbars shift with state and pane width.
- Before `ctrl+a` / Delete in a properties field, confirm the field has focus - on the canvas the same keys delete
  controls.
- Preview devices: the phone icon above the preview lists sizes (iPhone X = 375 x 812); an iPad Pro 12.9 renders
  portrait (1024 wide) - a good narrow-desktop test.

## Player and flows
- A player in a hidden tab is useless for verification ("Sign in required", tiny render). Use Studio Play, or have the
  user look, and prove the package from a flow run's trigger payload.
- Designer "Test -> Manually": click the Manually radio before Test, and fill the trigger text box by keyboard typing
  (form fill can leave it empty). The run appears in the flow's 28-day history.
- Dataverse Web API from a browser tab on the org origin (`<env url>/api/data/v9.2/WhoAmI` first, to prove the
  account) uses the page's cookies: env var values, flow state (`PATCH workflows(<id>)` `{statecode:1,statuscode:2}`)
  and the Git actions work there. A maker-portal sign-in does not restore an expired Dataverse session.

## Shell limits met on Windows
- Long inline scripts hit the command-line limit (`ENAMETOOLONG`): write them to the scratchpad and run the file.
- Write API responses to the scratchpad, not `/tmp` (node cannot resolve git-bash `/tmp`).
- PowerShell variables are case-insensitive: `$h` and `$H` are the same variable.
- MSYS `grep` strips CR before matching, so it cannot check CRLF - trust `git diff --stat` / `git ls-files --eol`.
