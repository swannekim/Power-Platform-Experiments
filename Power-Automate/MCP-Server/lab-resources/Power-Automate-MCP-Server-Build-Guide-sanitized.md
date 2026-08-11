# Building / Forking the Power Automate MCP Server — Step‑by‑Step Guide

> The LinkedIn post you saw (by <contributor-name>) calls it **"FlowRunner."** In the
> actual Microsoft repository it is the **FlowAgent MCP server**, shipped as the
> **`power-automate`** plugin inside **`microsoft/power-platform-skills`**. Same thing —
> ~50+ tools (the post cites 52) to create, edit, run, debug and deploy Power Automate
> cloud flows from an AI CLI. This guide shows where it lives and three ways to get it
> running, including the fork/copy route you asked for.

---

## 0. The single most important fact

The whole engine is **one self‑contained file**:

```
plugins/power-automate/server/mcp.mjs
```

It is a single ESM bundle — **stdio transport, all 50+ tools, all dependencies inlined**.
It needs **only Node.js 18+**. No `npm install`, no `npx`, no Docker, no remote host, no
published npm package. That is exactly why "just copy or fork it" is the *best* path for
you: you can lift that one file into any MCP‑capable client and own a working copy in
minutes.

---

## 1. Where it lives in the repo (exact map)

Repo: **`https://github.com/microsoft/power-platform-skills`** → folder **`plugins/power-automate/`**

```
power-platform-skills/
└── plugins/
    └── power-automate/
        ├── server/
        │   └── mcp.mjs        ← THE MCP SERVER (single self-contained file, Node 18+)
        ├── .mcp.json          ← launches mcp.mjs via a small Node bootstrap
        │                        (resolves PLUGIN_ROOT / CLAUDE_PLUGIN_ROOT, then
        │                        dynamically imports server/mcp.mjs)
        ├── skills/            ← verb-first skills: setup, browse-flows, create-flow,
        │                        build-flow, debug-flow, diagnose-flow, manage-flows,
        │                        manage-desktop-flows, route-environments
        ├── references/        ← shared docs the skills reference
        ├── .plugin/plugin.json      ← Open Plugins manifest (name/version/description)
        ├── .claude-plugin/          ← legacy manifest mirror (older subscriptions)
        ├── AGENTS.md          ← tool-routing rule
        ├── CLAUDE.md          ← plugin-local notes + pointer to the engine source
        └── README.md          ← plugin overview + capabilities
```

**Engine vs. plugin (important distinction):**

- **This folder is the *plugin*** — the marketplace-packaged surface: skills, MCP wiring,
  and the pre-built `server/mcp.mjs` bundle.
- **The *engine source*** (the TypeScript monorepo: `packages/core`, `packages/cli`) lives
  in a separate repo the README references as **`matow_microsoft/flow-agent`**. `mcp.mjs`
  is *generated* from that monorepo (`packages/cli/src/bin/mcp-stdio.ts`) via
  `npm run build` → `scripts/bundle-plugin-mcp.mjs`.
- ⚠️ **Honest caveat:** that `flow-agent` source monorepo does **not appear to be publicly
  accessible** at the time of writing (it reads like an internal Microsoft repo). The
  publicly available, buildable/copyable artifact is the **bundled `server/mcp.mjs`** in
  the marketplace repo above. So Paths A and B below are the ones anyone can do today;
  Path C only works if you can reach the `flow-agent` repo internally.

---

## 1½. Which path should *you* pick? (decision guide)

Answer one question: **do you want to change the server's behaviour?**

| Your goal | Path | Why |
|---|---|---|
| Just build flows with AI | **A** — install the plugin | Two commands, auto-updates, officially supported |
| Read / pin / audit the code, or run an old version | **B1** — fork + `--plugin-dir` | Your copy, but still uses the repo's tested `.mcp.json` |
| Wire the server into a non-plugin client (VS Code, Claude Desktop, your own agent) | **B2** — lift `mcp.mjs` | Raw MCP server, no skills wrapper |
| Actually modify tool behaviour | **C** — build from source | Only path where edits survive; needs the internal repo |

**Most people want Path A.** Forking (B) gets you a *copy*, not the ability to change
behaviour meaningfully — `mcp.mjs` is a generated bundle, so hand-edits are overwritten on any
rebuild and are painful to make (it's one ~1.6 MB minified ESM file). Choose B only if you
need to **pin a version** or **wire a client that doesn't support plugins**. Choose C only if
you can reach the internal `flow-agent` monorepo.

> Practical note: Paths A and B are **not mutually exclusive and can collide**. If the
> plugin is installed *and* you also register `flowagent` manually, you get two servers
> exposing identically-named tools and the agent may bind to the wrong one. Pick one.

### ⚠️ The prerequisite this guide originally understated: **model selection**

This matters more than which path you pick.

The FlowAgent server exposes **56 tools**. Driving them requires a model strong enough to
plan a multi-step tool sequence. In a real session on 2026-08-10, Copilot CLI's **Auto mode
selected `gpt-5-mini`**, which ignored all 56 tools and fell back to writing **ARM templates**
— producing Azure **Logic Apps** instead of Power Automate cloud flows, then narrating
imaginary progress for ~50 minutes. Zero MCP tool calls were ever made.

**Before asking for a flow, pin a capable model** (`/model` → Claude Opus/Sonnet or
GPT-5.3-Codex). See `SESSION-HISTORY-2026-08-10.md` for the full post-mortem.

Quick self-check that the plugin is actually being used:

- Ask *"List my Power Automate environments"* first. Real environment names = wired correctly.
- If you ever see the agent running `az`, `az deployment`, or writing ARM JSON for a
  **flow** task — **stop it**. It has fallen off the MCP path.

---

## 2. Prerequisites (all three paths)
| Requirement | Why | Check |
|---|---|---|
| **Node.js 18+** | Runs `mcp.mjs` | `node --version` |
| **Azure CLI + `az login`** | Auth — the server uses a two-provider model: **Azure CLI + MSAL** for Power Platform / connector endpoints | `az account show` |
| **An MCP-capable client** | To talk to the server | Claude Code, GitHub Copilot CLI, Claude Desktop, VS Code (MCP), or your own agent |
| *(Optional)* **pac CLI** | Some Power Platform ALM ops | `pac --version` |
| *(Path C only)* **git + npm** | Build from source | — |

> Auth note: after wiring the server in, run **`az login`** once so the tools can reach your
> Power Platform environments. No API keys or secrets are stored by the server.
>
> ⚠️ **Two important caveats learned the hard way:**
>
> 1. **Check before you log in.** Run `az account show` first. If it already returns the right
>    account, *don't* run `az login` — and never let an AI agent run it, because
>    `az login --use-device-code` blocks on interactive input and the agent will simply hang.
> 2. **FlowAgent has its own MSAL cache, separate from Azure CLI**, at
>    `%LOCALAPPDATA%\flowagent\` (`msal-cache\` + `tokens\`). If you work across tenants it can
>    silently pick the wrong cached account (it falls back to `accounts[0]`). Pin it with:
>    ```powershell
>    $env:PA_TENANT_ID = "<your-tenant-guid>"
>    ```
>    …and if it's already wrong, delete the contents of `%LOCALAPPDATA%\flowagent\msal-cache`
>    and `\tokens` to force a clean re-auth.
>
> Useful env vars in the bundle: `PA_TENANT_ID`, `PA_DEFAULT_ENVIRONMENT`, `PA_CLIENT_ID`,
> `PA_CLOUD`, `PA_MCP_DEBUG`, `FLOWAGENT_MSAL_CACHE_DIR`, `FLOWAGENT_TOKEN_CACHE_DIR`.

---

## 3. Path A — Just install the plugin (recommended for most)

Fastest, officially supported, auto-updates. Run these **inside a Claude Code or GitHub
Copilot CLI session**:

```
/plugin marketplace add microsoft/power-platform-skills
/plugin install power-automate@power-platform-skills
```

Then just ask, e.g.:

> "Build a flow that sends a Teams message when a SharePoint item is created."

This installs the skills **and** the MCP server together, wired via the plugin's own
`.mcp.json`. Nothing to build. **Choose this unless you specifically want to own/customize
the server.**

---

## 4. Path B — Fork / copy the MCP server (what you asked for — the best route)

You get your **own copy** you can inspect, pin, and customize. Two options, pick one.

### Option B1 — Run your fork as a local plugin (cleanest — uses the repo's own wiring)

This loads the skills **and** the server via the repo's tested `.mcp.json`, so you don't
hand-author any config.

```bash
# 1. Fork microsoft/power-platform-skills on GitHub (button in the top-right), then:
git clone https://github.com/<your-username>/power-platform-skills.git
cd power-platform-skills

# 2. Confirm the engine file is present
node --version                                   # must be >= 18
ls plugins/power-automate/server/mcp.mjs         # the single-file server

# 3. Authenticate to Power Platform
az login

# 4. Launch Claude Code pointing at your local plugin copy
claude --plugin-dir "$(pwd)/plugins/power-automate"
```

Now everything runs from **your** clone/fork — edit skills or the server locally and they
take effect on next launch.

### Option B2 — Lift just the server into any MCP client (pure standalone)

If you only want the raw MCP server (no skills wrapper) wired into a client of your choice,
copy the single file and point Node at it.

```bash
# Copy the one file you need
cp plugins/power-automate/server/mcp.mjs  ~/flowagent-mcp/mcp.mjs
az login
```

Then add a standard **stdio** MCP server entry to your client. The repo's own `.mcp.json`
wraps this with a bootstrap that auto-resolves the plugin folder; for a hand-rolled copy you
simply give Node the **absolute path** to the file:

```json
{
  "mcpServers": {
    "flowagent": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/flowagent-mcp/mcp.mjs"]
    }
  }
}
```

Where that JSON goes, by client:

- **Claude Code** — save as `.mcp.json` in your project root, **or** run:
  `claude mcp add flowagent -- node /ABSOLUTE/PATH/TO/mcp.mjs`
- **Claude Desktop** — merge into `claude_desktop_config.json`
  (macOS: `~/Library/Application Support/Claude/`; Windows: `%APPDATA%\Claude\`), then restart.
- **VS Code + GitHub Copilot** — see the dedicated **"VS Code + GitHub Copilot"** section
  right below for the full walkthrough. ⚠️ VS Code's schema uses a top-level **`servers`** key,
  **not** `mcpServers` — copying the wrong shape is the most common reason it fails to load.
- **GitHub Copilot CLI** — also supports stdio MCP servers, but the plugin install in Path A
  is the smoother supported route there.
- **Your own agent** — spawn `node /ABSOLUTE/PATH/TO/mcp.mjs` and speak MCP over stdio.

### Verify it works

```bash
# The server waits on stdio (no output = healthy; Ctrl+C to exit)
node ~/flowagent-mcp/mcp.mjs
```

Then in your client, ask it to **list your Power Automate environments** or **list flows** —
if it returns your real environments/flows, auth + wiring are correct.

---

## 4½. VS Code + GitHub Copilot — complete setup (tailored)

This wires your **copied FlowAgent server** (from Path B) into VS Code so its tools appear in
**GitHub Copilot Chat's Agent mode**.

### Prerequisites
- **VS Code** (current release — MCP support is generally available) with the **GitHub Copilot**
  and **GitHub Copilot Chat** extensions, signed in with a Copilot-enabled account.
- **Node.js 18+** and your copied server file from Path B (e.g. `~/flowagent-mcp/mcp.mjs`).
- **Azure sign-in:** open the VS Code integrated terminal and run **`az login`** once.

### Step 1 — Add the server (pick one)

**A) Guided (Command Palette) — easiest**
1. `Ctrl/Cmd+Shift+P` → **MCP: Add Server**.
2. Choose **Command (stdio)**.
3. Command: `node`  ·  Args: the **absolute path** to your `mcp.mjs`.
4. Name it `flowagent`; choose **Workspace** (this project) or **Global** (all workspaces).
   VS Code writes the entry into `.vscode/mcp.json` (workspace) or your user config.

**B) Manual — edit `.vscode/mcp.json`**
Create `.vscode/mcp.json` in your project. ⚠️ **VS Code's top-level key is `servers`** (not
`mcpServers` like Claude Desktop / Claude Code):

```json
{
  "servers": {
    "flowagent": {
      "type": "stdio",
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/flowagent-mcp/mcp.mjs"]
    }
  }
}
```

If you keep the copy inside the repo, you can use the workspace variable instead of an
absolute path:
`"args": ["${workspaceFolder}/plugins/power-automate/server/mcp.mjs"]`

**C) One-liner from the terminal**
```bash
code --add-mcp "{\"name\":\"flowagent\",\"command\":\"node\",\"args\":[\"/ABSOLUTE/PATH/TO/mcp.mjs\"]}"
```

### Step 2 — Trust & start
On first start VS Code shows a **trust dialog** — review and confirm (it's your own local file).
Then start/verify via **MCP: List Servers** → select `flowagent` → **Start Server** /
**Show Output** (server logs live here if anything fails). You can also use the inline code-lens
**Start** action directly in `mcp.json`.

### Step 3 — Use it in Copilot Chat (Agent mode)
1. Open **Chat** (`Ctrl+Alt+I`, or `Ctrl/Cmd+I`).
2. In the chat **mode dropdown**, switch to **Agent** (MCP tools only surface in Agent mode).
3. Click **Configure Tools** and confirm the **`flowagent`** tools are enabled.
4. Prompt, e.g. *"List my Power Automate environments"* or *"Build a flow that posts to Teams
   when a SharePoint item is created."* Approve tool calls when prompted (or pre-trust them).

### Optional
- **Cross-workspace:** put the same block in your user config via **MCP: Open User
  Configuration** so it's available in every workspace.
- **Secrets:** don't hardcode anything — this server authenticates via `az login`, so no keys
  belong in `mcp.json`. If you ever need a value, use VS Code **input variables**, not literals.
- **Sandbox (macOS/Linux only):** add `"sandboxEnabled": true` to the server entry to restrict
  its file/network access (not available on Windows).
- **Auto-restart on config change:** enable the experimental `chat.mcp.autoStart` setting.

### VS Code-specific troubleshooting
| Symptom | Fix |
|---|---|
| Tools don't appear in chat | You're in Ask/Edit mode — switch the chat to **Agent**, then **Configure Tools** → enable `flowagent` |
| Server won't start | **MCP: List Servers → Show Output** for the log; confirm Node 18+ and that the path is **absolute** |
| Auth error / empty results | Run `az login` in the integrated terminal; confirm `az account show` points at the right tenant |
| Changed config but nothing happens | Restart via **MCP: List Servers → Restart**, or enable `chat.mcp.autoStart` |
| Wrong tenant / environment | Re-run `az login`; use the `route-environments` capability |

> Source: VS Code docs — *Add and manage MCP servers in VS Code*
> (code.visualstudio.com/docs/agent-customization/mcp-servers).

---

## 5. Path C — Build from the source monorepo (true "from reference code")

Only doable if you can reach the **FlowAgent** engine repo (referenced as
`matow_microsoft/flow-agent`; appears internal). If you have access:

```bash
git clone <flow-agent repo URL>
cd flow-agent
npm install
npm run build          # regenerates the bundle from packages/cli/src/bin/mcp-stdio.ts
                       # via scripts/bundle-plugin-mcp.mjs -> plugins/.../server/mcp.mjs
```

For local development against the monorepo, point your client at the repo-root shim instead
of the bundle:

```json
{ "mcpServers": { "flowagent": { "command": "node", "args": ["/abs/path/flow-agent/dist/mcp.js"] } } }
```

A publishable `@microsoft/power-automate-mcp` npm package *may* follow later, but neither the
plugin nor these steps depend on it today.

---

## 6. Customizing your copy

- **Quick throwaway tweaks:** you *can* patch `server/mcp.mjs` directly, but remember it's a
  generated bundle — a rebuild (Path C) overwrites it.
- **Real changes:** belong in the engine source (`packages/core`, `packages/cli`) and are
  compiled back into `mcp.mjs` via `npm run build`. Keep your customizations there so they
  survive updates.
- Read the plugin's **`CLAUDE.md`** and **`AGENTS.md`**, and the FlowAgent repo's `CLAUDE.md`
  (the authoritative reference for flow-definition rules, the two-provider auth model, the
  full CLI/MCP tool surface, and the error reference).

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Server starts but no flows returned | Not authenticated → run `az login`; confirm `az account show` points at the right tenant |
| "node: command not found" or syntax errors | Node < 18 → upgrade to Node.js 18+ |
| Client can't find the server | Use an **absolute** path in `args`; relative paths break |
| Wrong / missing environment | Use the `route-environments` skill, or check environment routing (Default-env IDs + sovereign clouds are handled by recent fixes) |
| Approval prompts on every tool | Pre-approve tools in your client (e.g. Claude Code `defaultMode: acceptEdits` + an allow-list for `node`, `az`, `pac`) — only in trusted/sandboxed setups |
| **`/plugin install` fails: `Access is denied. (os error 5)`** (Windows) | A **file lock**, not permissions — running Copilot CLI sessions hold handles on `~/.copilot/installed-plugins/*`, and the installer can't replace a stale folder from a previous partial install. **Close every CLI session** (incl. IDE/sidebar) and retry. Running as Administrator does **not** help. Last resort: replace the folder *contents* in place and register the plugin in `~/.copilot/config.json` + `settings.json`. |
| `Marketplace "…" already registered` | Harmless — it's already in `settings.json` → `extraKnownMarketplaces`. Skip the `add` and go straight to `install`. |
| **Agent builds Azure Logic Apps instead of Power Automate flows** | The model is too weak and fell back to ARM. Pin a capable model with `/model`. Logic Apps live in Azure and will **never** show up in `make.powerautomate.com`. |
| Agent says "working…" but nothing happens | It's narrating without calling tools. Interrupt (**Esc**) and tell it explicitly to use the flowagent MCP tools. |
| `ServiceToServiceEnvironmentNotFound … could not be found in the tenant '<guid>'` | FlowAgent picked the wrong cached account. Set `PA_TENANT_ID` and clear `%LOCALAPPDATA%\flowagent\msal-cache` + `\tokens`. |
| `No environment specified and no default set` | Either call `set_current_env` **in the same server session**, or set `PA_DEFAULT_ENVIRONMENT=<env-guid>` (the pin does not persist across process restarts for env-less calls). |
| Flow rejected on save: `extra-authentication` | Remove `"authentication": "@parameters('$authentication')"` from **action** inputs — the Flow API injects it. Keep it on the trigger. Run `validate_flow` + `preflight_flow` before `create_flow` to catch this. |
| Connector operation not found (e.g. `OnNewItems`) | Don't guess operation IDs. Use `search_operations` / `get_connector`. SharePoint "When an item is created" is **`GetOnNewItems`**; Teams post is **`PostMessageToConversation`**. |
| Connector params reject display names | Resolve them to GUIDs first: `list_datasets` / `list_tables` (SharePoint) and `resolve_entity` (Teams `groupId` / `channelId`). |

---

## 8. Source references (exact names, for traceability)

- **Marketplace repo:** `microsoft/power-platform-skills`
- **Plugin folder:** `plugins/power-automate/`
- **MCP server file:** `plugins/power-automate/server/mcp.mjs`
- **Launcher:** `plugins/power-automate/.mcp.json`
- **Engine source (referenced, likely internal):** `matow_microsoft/flow-agent` — monorepo
  `packages/core`, `packages/cli`; bundle generated from `packages/cli/src/bin/mcp-stdio.ts`
- **Product name in the repo:** *FlowAgent MCP server* (the LinkedIn post's "FlowRunner")

---

### Recommendation

- **Want it working now?** → Path A (two commands).
- **Want to own/fork/customize it (your stated goal)?** → **Path B, Option B1** — fork, clone,
  `claude --plugin-dir .../plugins/power-automate`. It's the single-file server plus skills,
  running entirely from your copy.
- **Want to build from raw TypeScript source?** → Path C, but only if you can reach the
  internal `flow-agent` repo.

> **Revised recommendation after real-world use (2026-08-10):** start with **Path A**, even if
> your end goal is a fork. Path A gets you a known-good baseline in two commands, so when
> something breaks you know it's *your* change and not the wiring. Move to B1 only once you
> have a concrete reason to pin or modify.
>
> And regardless of path: **pinning a capable model matters more than the path you choose.**
> A weak model with a perfectly installed plugin produces nothing (or worse — plausible-looking
> Logic Apps). See `SESSION-HISTORY-2026-08-10.md`.

---

## 9. Verified working sequence (<your-environment-name>, 2026-08-10)

End-to-end proof that Path A + a capable model works. Every step is an MCP tool call — no
`az`, no ARM, no import packages.

```
set_current_env            → <your-environment-name>
pick_or_create_connection  → shared_sharepointonline   (Connected, silent first-party auth)
pick_or_create_connection  → shared_teams              (Connected)
list_datasets / list_tables→ site + list GUID
resolve_entity             → Teams groupId + channelId (confidence: exact)
search_operations          → GetOnNewItems / PostMessageToConversation
resolve_refs               → connection references JSON
validate_flow              → catches errors before save
preflight_flow             → "overall": "ready"
create_flow                → flow created
publish_flow               → state: Started
```

Prompt that reliably keeps the agent on the MCP path:

> Use the **flowagent MCP tools only**. Do **not** use `az`, ARM templates, or Logic Apps.
> Do not run `az login` — I'm already authenticated.
> Sequence: `set_current_env` → `pick_or_create_connection` → `resolve_entity` →
> `validate_flow` → `preflight_flow` → `create_flow` → `publish_flow`.
