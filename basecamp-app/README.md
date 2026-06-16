# LP-0008 AI Agent — Basecamp Mini-App

Owner console for the LP-0008 agent module. Lets the module owner monitor agent status,
approve or reject pending spend requests, send messages over the owner channel, and update
spending-limit config — all from inside the Logos Basecamp interface.

---

## What it does

| Panel | What it calls |
|---|---|
| Agent Status | `meta.status()` — balance, active tasks, pending approvals, period spend |
| Pending Approvals | `approve_pending({ task_id })` / `reject_pending({ task_id })` |
| Send Message | `owner.send({ message })` — sends text on the E2E owner 1:1 channel |
| Spending Limits / Config | `meta.configure({ key, value })` — per_tx_limit, per_period_limit, period_seconds, owner_address |
| Skills | `meta.skills()` — lists all registered skills |

All calls go through `window.logos.callModule(method, params)`, the bridge that Basecamp
injects into the WebView when a mini-app is active.  If that bridge is not present (local
`file://` preview), the app falls into **MOCK MODE** and shows fixture data.

---

## Load into Basecamp (local build required)

Released Logos desktop builds reject user-supplied mini-apps. You need a local Basecamp
build — the same requirement as LP-0002, LP-0003, and LP-0005.

### 1. Build Logos desktop locally

Follow the upstream Logos build instructions from the
[logos-co/desktop](https://github.com/logos-co/desktop) repository. Ensure your build
includes the `agent_module` from this prize (scaffold/).

### 2. Start the agent daemon

On your remote node (or localhost for testing), start `logoscore` with the agent module:

```
logoscore -D --load-module ./agent_module.so
```

The agent must be running before Basecamp loads the mini-app, so that `window.logos.callModule`
can route calls to it.

### 3. Load this mini-app in Basecamp

1. Open your local Logos desktop build and navigate to **Basecamp**.
2. Click **Load local app** (or the equivalent button in your build).
3. Point it at this directory (`basecamp-app/`). Basecamp reads `module.json` first to identify
   the app, then loads `index.html` in the embedded WebView.
4. The **Agent Status** panel loads automatically. Click **Refresh** or **Load** on other panels.

### 4. Local file preview (MOCK MODE, no daemon needed)

To inspect the UI without a running agent:

```
open basecamp-app/index.html
```

The app detects that `window.logos` is absent and renders a yellow MOCK MODE banner. All
buttons work and return fixture data so the layout can be verified.

---

## Bridge API

The bridge is `window.logos.callModule(method, params) → Promise<any>`.

Basecamp injects this into every mini-app WebView. The method strings route to the
corresponding `agent_module` C++ handlers:

| Method string | Agent handler | Returns |
|---|---|---|
| `"meta.status"` | `agent_module::meta_status()` | `{ online, balance, active_tasks, pending_approvals, period_spent, pending[] }` |
| `"meta.skills"` | `agent_module::meta_skills()` | `{ skills: [{ name, description }] }` |
| `"meta.configure"` | `agent_module::meta_configure({ key, value })` | `{ ok, key, value }` |
| `"approve_pending"` | `agent_module::approve_pending({ task_id })` | `{ ok, task_id, executed }` |
| `"reject_pending"` | `agent_module::reject_pending({ task_id })` | `{ ok, task_id, cancelled }` |
| `"owner.send"` | `agent_module::owner_send({ message })` | `{ ok, delivered }` |

The exact shape of `window.logos.callModule` is not publicly specified in the Logos
documentation as of this writing. This app mirrors the pattern described in the LP-0008
architecture (`ARCHITECTURE.md §4`) and follows the same calling convention used by sibling
basecamp apps. If the released Basecamp WebView bridge uses a different method name or
signature, update the `callModule` wrapper in `index.html` accordingly — the rest of the UI
does not need to change.

---

## Files

```
basecamp-app/
  index.html    owner console UI (single-file, no build step, no external deps)
  module.json   Basecamp mini-app manifest
  README.md     this file
```

No build step. No npm. No bundler. The app is a plain HTML file that runs in the Basecamp
WebView as-is.
