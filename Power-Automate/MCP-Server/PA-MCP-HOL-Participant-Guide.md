# Building Power Automate Flows with AI — Participant Hands-On Guide

### L300–400 · GitHub Copilot CLI + the FlowAgent MCP Server · KT delivery

> **You already know how to click. Today you learn how to describe — and how to debug what the
> agent built.**

**Duration:** 3h 15m · **You will build:** 3 production-shaped cloud flows
**Environment:** one shared Power Platform environment — **everything you create gets your name on it**

---

## Table of contents

| Part | Time | What happens |
|---|---|---|
| [0. Before you start](#part-0--before-you-start) | — | Read this on the way in |
| [1. Setup](#part-1--setup-020) | 0:00–0:20 | HOL server → Copilot CLI → plugin → first tool call |
| [2. Warm-up](#part-2--warm-up-meet-the-tools-020035) | 0:20–0:35 | Meet the skills. Prove auth. One green result. |
| [3. Scenario 1 — SLA Triage](#part-3--scenario-1--sla-aware-request-triage-035130) | 0:35–1:30 | Branching, adaptive cards, SLA timers, error handling |
| [4. Break](#part-4--break-130140) | 1:30–1:40 | Leave your flows running |
| [5. Scenario 2 — Flow Health Guardian](#part-5--scenario-2--flow-health-guardian-140240) | 1:40–2:40 | Automation that watches automation |
| [6. Scenario 3 — Access Provisioner](#part-6--scenario-3--self-service-access-provisioner-240305) | 2:40–3:05 | Approvals + Entra + auto-revocation |
| [7. Package it](#part-7--package-what-you-built-305312) | 3:05–3:12 | Solution export = flow-as-code |
| [8. Debrief](#part-8--debrief-312315) | 3:12–3:15 | When *not* to use the agent |
| [Appendix A — Troubleshooting](#appendix-a--troubleshooting-reference) | — | Every error we actually hit, and the fix |
| [Appendix B — Skills reference](#appendix-b--skills-reference) | — | What each skill does |
| [Appendix C — Your environment card](#appendix-c--your-environment-card) | — | Fill this in during setup |

---

# Part 0 — Before you start

## 0.1 What you are actually learning today

You are **not** here to learn that an AI can write a flow. You are here to learn a loop:

```
describe  →  the agent resolves real IDs  →  validate  →  create  →  run  →  read the failure  →  fix
```

…without leaving the terminal, with every flow definition versionable in Git.

The three flows were chosen because each contains something genuinely tedious in the designer —
computed due dates, `Configure run after`, adaptive cards that wait for a human, parallel
branches, Entra calls. Work that takes 40 minutes of clicking collapses into a sentence.

**But the honest part matters more.** During the build of these exact flows, the agent:

- invented a connector operation that does not exist (twice),
- passed a value that looked obviously correct and was rejected at runtime,
- and, on a weaker model, spent 50 minutes building **Azure Logic Apps** for a Power Automate request.

You will see all three today. That is the point. *The agent builds what you ask for, including
the mistakes.*

## 0.2 Your name suffix — read this before you type anything

We are all in **one shared environment**. Every flow you create must end with your name:

```
HOL S1 — IT Request Triage — sage
```

And every SharePoint item you create for testing must **start** with your name in square brackets:

```
[sage] Production database unreachable
```

Without this, twenty people will be staring at one Teams channel unable to tell whose message is
whose, and someone will delete someone else's flow.

> **Pick your suffix now and write it on the card in [Appendix C](#appendix-c--your-environment-card).**
> Use lowercase, no spaces. It appears in ~15 prompts today.

## 0.3 What the has already been built for you

You will **not** create SharePoint lists today — that eats 20 minutes and teaches nothing about
the MCP server. These already exist on the Contoso site:

| List | Used by | Contains |
|---|---|---|
| `IT-Requests` | Scenario 1 | 3 history rows. You add test rows. |
| `Routing-Table` | Scenario 1 | 3 rows — **and deliberately no `Incident` row** |
| `Flow-Health-Log` | Scenario 2 | Empty by design |
| `Privileged-Groups` | Scenario 3 | 4 rows with real Entra group IDs |
| `Access-Requests` | Scenario 3 | 1 history row. You add test rows. |

Also pre-built: the `IT-Ops` Teams channel, four throwaway `HOL-` Entra groups, and three
deliberately-broken "canary" flows that Scenario 2 will discover.

---

# Part 1 — Setup (0:20)

> ⏱️ **This part is not optional and not fast to redo.** Half the room fails in the same way if
> steps 1.4 and 1.6 are skipped.

## 1.1 Open your workspace

1. Log into the **HOL server** with the credentials on your desk card.
2. Open **VS Code**. `File → Open Folder…` → the `MCP-Server` folder on the Desktop.

You should see:

```
MCP-Server/
├── README.md
├── PA-MCP-HOL-Participant-Guide.md       ← English participant guide
├── PA-MCP-HOL-Participant-Guide-KO.md    ← Korean participant guide
├── lab-resources/
│   ├── Demo data pack Excel file (.xlsx) ← seed data + environment references
│   └── Power-Automate-MCP-Server-Build-Guide-sanitized.md
└── sample-pa-flows/
    ├── KTHandsOn_1_0_0_0.zip             ← reference solution (all 3 flows)
    ├── HOLS1ITRequestTriage_1_0_0_0.zip  ← reference solution, S1 only
    ├── HOLS2FlowHealthGuardian_1_0_0_0.zip ← reference solution, S2 only
    └── HOLS3AccessRequestProvision_1_0_0_0.zip ← reference solution, S3 only
```

3. Open the **demo data pack Excel file** in `lab-resources/` and go to the
   **`Environment-Reference`** sheet. Copy those values onto
   [Appendix C](#appendix-c--your-environment-card) now. You will need them repeatedly.

> The `.zip` files in `sample-pa-flows/` are the **answer key**. If your flow gets stuck beyond
> recovery, import the matching solution and carry on. Try not to open them before you have
> built your own.

## 1.2 Verify the prerequisites

Open a **PowerShell terminal** in VS Code (`` Ctrl+` ``) and run:

```powershell
node --version      # must be v18 or higher
az --version        # Azure CLI must be present
```

Both present? Move on. If not, raise a hand — do not try to install anything yourself.

## 1.3 Check your Azure sign-in — **do not run `az login`**

```powershell
az account show
```

If that returns your account, **you are done. Do not sign in again.**

> ### ⛔ The single most common way to lose 30 minutes
> Never let the AI agent run `az login`. `az login --use-device-code` prints a code and then
> **blocks**, waiting for browser input the agent cannot provide. It hangs forever and the agent
> will cheerfully tell you it is "working" the whole time.
>
> In the recorded build this exact mistake cost 1m 41s of hang and then an hour of confusion.
> **If a real login is needed, run it yourself in the terminal.**

## 1.4 Pin the tenant and environment

FlowAgent keeps its **own** authentication cache, separate from the Azure CLI. If you skip this,
it can silently query the wrong tenant and tell you your environment does not exist.

```powershell
$env:PA_TENANT_ID           = "<tenant-guid-from-your-card>"
$env:PA_DEFAULT_ENVIRONMENT = "<environment-guid-from-your-card>"
```

**Why `PA_DEFAULT_ENVIRONMENT` matters:** `set_current_env` only holds for the life of one MCP
server process. Set the variable and an entire class of "No environment specified" errors
disappears.

## 1.5 Start Copilot CLI — and **pin the model**

```powershell
copilot
```

Then, **before typing anything else**:

```
/model
```

Choose **Claude Sonnet/Opus** or **GPT-5.3-Codex**. **Never leave it on Auto.**

> ### ⛔ Why this is step zero, not a footnote
> In the recorded failure, Auto mode selected `gpt-5-mini`. The FlowAgent server loaded
> successfully with all **56 tools available** — and the model invoked **exactly zero** of them.
> Instead it fell back to what it knew: ARM templates. It produced **Azure Logic Apps**, which
> are a different product, live in Azure, and never appear in `make.powerautomate.com`.
>
> Then it narrated imaginary progress for 50 minutes: *"Proceeding now…"*, *"obtaining an access
> token…"*, *"I'll notify you when the consent URL is ready…"* — while making no tool calls at all.
>
> A weak model with a perfectly installed plugin produces nothing, or worse: something
> plausible-looking and useless.

## 1.6 Install the plugin

Type these **inside the Copilot CLI session**:

```
/plugin marketplace add microsoft/power-platform-skills
```

```
/plugin install power-automate@power-platform-skills
```

Then **restart the CLI** (exit and run `copilot` again) so the MCP server loads.

**Expected:** on restart, the FlowAgent MCP server starts and exposes **56 tools**.

<details>
<summary><b>If you see <code>Marketplace "power-platform-skills" already registered</b></code></summary>

Harmless. It is already registered. Skip the `add` and run the `install` line only.
</details>

<details>
<summary><b>If you see <code>Failed to install plugin: Access is denied. (os error 5)</b></code></summary>

This is a **file lock, not a permissions problem** — running as Administrator will not help.
A previous Copilot CLI session (including one embedded in VS Code's sidebar) is holding a handle
on `~/.copilot/installed-plugins/`.

**Close every Copilot CLI and VS Code window**, then retry. Raise a hand if it persists.
</details>

## 1.7 Run the `setup` skill

```
/setup
```

This walks the prerequisites: Node, Azure CLI, sign-in state, token access, and whether the
FlowAgent tools are wired. It ends by listing your environments.

**This is your first skill.** Note what it did *not* do: it did not ask you to configure
anything. It checked, reported, and fixed what it could.

## 1.8 Paste the guardrail prompt

This is the most valuable thing you will type today. **Paste it as your first real message in
every lab session:**

```
Use the flowagent MCP tools only. Do not use az, ARM templates, or Logic Apps.
Do not run az login — I am already authenticated.
Always resolve display names to GUIDs with resolve_entity / list_tables / search_operations.
Never guess an operation ID or an enum value — look it up and tell me if it does not exist.
Sequence: set_current_env → pick_or_create_connection → resolve_entity →
validate_flow → preflight_flow → create_flow → publish_flow.
When adding to a flow that already exists, use edit_flow or update_flow — do not delete
and recreate it, and do not re-send connectionRefs on an update.
SharePoint update actions require item/Title even when only changing Status.
After each tool call, tell me which tool you called and what it returned.
If you cannot complete a step with an MCP tool, stop and ask me — do not improvise a workaround.
```

Five clauses in there are doing real work:

| Clause | What it prevents |
|---|---|
| *"flowagent MCP tools only… no ARM or Logic Apps"* | The 50-minute Logic Apps detour |
| *"never guess… tell me if it does not exist"* | Invented operation IDs that fail at save or, worse, at runtime |
| *"use edit_flow or update_flow — do not delete and recreate"* | Your flow ID changing under you between prompts 3, 4 and 5 |
| *"do not re-send connectionRefs on an update"* | `connection reference … could not be found` — the one real way an update fails |
| *"SharePoint update actions require item/Title"* | A publish-time rejection that `validate_flow` does **not** catch |
| *"tell me which tool you called"* | Silent stalling — you can *see* whether work is happening |

> ### Why two of those clauses exist
> The prompt ladder in each scenario is **incremental**: Prompt 2 creates the flow, and Prompts
> 3–5 add to it. Both `edit_flow` (surgical) and `update_flow` (whole definition) work correctly
> on these flows — **verified**. But an update that re-sends `connectionRefs` fails, because
> `create_flow` places the flow in a solution where connections become *connection references*
> with different logical names. Telling the agent not to re-send them removes the only failure
> mode there.
>
> And `item/Title` is required on **every** SharePoint update, even a status-only one. That error
> appears at **publish**, after `validate_flow` and `preflight_flow` have both passed clean.

## 1.9 Learn the stall signal

If the agent says **"Proceeding now…"** and you see **no tool call**, press **Esc**.

Narration is not work. Zero tool calls means the plugin is not being used. Interrupt early and
restate: *"Use the flowagent MCP tools."*

---

# Part 2 — Warm-up: meet the tools (0:20–0:35)

Goal: everyone gets one green result, and you learn the discipline that makes the rest work.

## 2.1 Prove the plugin is wired

```
List my Power Automate environments.
```

**Expected:** real environment names, including the shared lab environment.

If you get anything else — an apology, a generic explanation, an offer to "help you get
started" — **the plugin is not being used or your model is too weak.** Go back to 1.5. Do not
continue.

## 2.2 Try the `browse-flows` skill

```
/browse-flows
```

Explore the environment and its flows. You will see flows other users of this environment had already built.

## 2.3 The habit that prevents most failures: **resolve before you build**

```
Set my environment to <env-name>. Then:
1. list the SharePoint lists on https://<tenant>.sharepoint.com/sites/Contoso
   and show me the columns of IT-Requests and Routing-Table
2. resolve the Teams team "Contoso" and the channel "IT-Ops" to GUIDs
3. show me which connections already exist and their status
Do not create anything yet — just report what you resolved.
```

Copy every GUID it returns onto [Appendix C](#appendix-c--your-environment-card).

### Why this is not busywork

Connector operations do **not** accept display names. A path like
`/v1/teams/Contoso/channels/IT-Ops/messages` looks reasonable and is **always wrong** — the real
connector needs GUIDs like `19:689fec82…@thread.tacv2`.

Watch for the `confidence` field on `resolve_entity`. You want **`exact`**. If it returns
`ambiguous`, it will list alternatives — **confirm before you build**, or you will provision
against the wrong Teams channel.

## 2.4 Watch the agent look something up

```
What operations does the SharePoint connector expose for a "when an item is created"
trigger? Give me the exact operation ID. Do not guess.
```

**Expected:** `GetOnNewItems`.

The intuitive guess is `OnNewItems`. It does not exist. In the recorded build, four out of four
guessed identifiers were wrong:

| Guessed | Actual | Found with |
|---|---|---|
| `OnNewItems` | **`GetOnNewItems`** | `search_operations` |
| `PostCardToConversationAndWaitForResponse` | ❌ does not exist at all | `get_operation_details` |
| `CustomResponses` | **`CustomResponse`** (singular) | `invoke_operation` → `GetApprovalTypes` |
| `ApprovalCreationInput/…` | **`WebhookApprovalCreationInput/…`** | `resolve_params` |

Each wrong guess costs a full create → publish → fail cycle. A read-only lookup costs seconds.

✅ **Checkpoint:** real environments listed, team + channel resolved as `exact`, and you know why
`GetOnNewItems` is not `OnNewItems`.

---

# Part 3 — Scenario 1 — SLA-Aware Request Triage (0:35–1:30)

## 3.1 The business case

Every IT team has an intake list. The work is not the ticket — it is the **babysitting**:
assigning it, nudging the owner, noticing the SLA is about to breach, escalating to a manager.
This flow does all four, and never forgets.

## 3.2 What you will learn

**About flows:**
- Data-driven routing — owners and SLAs come from a lookup table, not hard-coded values
- Computed due dates with expressions you would normally hand-write and typo
- An adaptive card that **waits for a human**, plus an approval with custom responses
- A real SLA timer inside a running instance, and why it must run in **parallel**
- `Scope` + `Configure run after` — the thing 80% of production flows are missing

**About building with the agent:**
- Why `validate_flow` and `preflight_flow` before every create saves cycles
- That the platform's own error messages are precise, and the agent can act on them
- That the agent is a **debugger**, not just a generator

## 3.3 The architecture you are aiming for

```
TRIGGER  SharePoint · When an item is created (IT-Requests, polls 1 min)
│
└─ SCOPE "Triage"
   ├─ Get the routing row for this RequestType
   ├─ Compute the SLA minutes from Priority, and DueBy = now + SLA
   ├─ Update the item: AssignedTo, Status = Assigned, DueBy
   │
   ├── BRANCH A — Switch on Priority
   │     ├─ P1 → adaptive card to IT-Ops + approval (Acknowledge / Reassign)
   │     ├─ P2 → Teams chat to the owner
   │     └─ P3 → email to the owner
   │
   └── BRANCH B — wait until 1 minute before DueBy      ← runs in PARALLEL with A
         → re-read the item
         → if Status is still not In Progress / Closed → Escalate + post to IT-Ops

SCOPE "Handle failure"  runs only if Triage failed or timed out
   → report the failing action + error to IT-Ops → terminate as Failed
```

> ### ⚠️ Why Branch B is parallel — a design bug worth understanding
> The obvious design puts the SLA delay **after** the Switch. But the P1 branch waits for a
> human. Sequentially, if nobody clicks, the flow **never reaches the escalation step** — so P1,
> the priority that most needs an SLA, is the only one that can never escalate.
>
> This was in the original lab design and was only caught by building it. Ask the agent for the
> parallel version, as the prompts below do.

## 3.4 The prompt ladder

### Prompt 1 — ground the agent

```
Set my environment to <env-name>. Show me the columns of the SharePoint lists
IT-Requests and Routing-Table, and resolve the Teams team "Contoso" and channel
"IT-Ops" to GUIDs. Report what you resolved. Do not create anything yet.
```

### Prompt 2 — build the spine

```
Create a flow named "HOL S1 — IT Request Triage — <yourname>" in this environment.

Trigger: when an item is created in the SharePoint list IT-Requests.
Then: get items from Routing-Table filtered to Title equal to the new item's
RequestType, and take the first match.
Update the new item with AssignedTo = the routing row's OwnerEmail,
Status = "Assigned", and DueBy = utcNow() plus the SLA minutes for the item's
Priority (SLAMinutes_P1 / _P2 / _P3 on the matched routing row).

Choice columns come through as objects — read them as RequestType/Value and
Priority/Value. Use addMinutes with an integer.
Validate and preflight before creating. Do not publish yet.
```

> **Why the last paragraph is there.** `addMinutes`/`addHours`/`addDays` require **integer**
> arguments. A fractional value saves cleanly and then throws **at runtime** — the most expensive
> kind of bug. And if you read `Priority` instead of `Priority/Value`, the Switch silently falls
> through to its default: every request gets the P3 email and *nothing looks broken*.

### Prompt 3 — the notification branch

```
Add a Switch on the trigger item's Priority/Value.

P1: post an adaptive card to the Teams channel IT-Ops showing the request title,
type, requester and DueBy. Then start an approval with custom responses
"Acknowledge" and "Reassign", assigned to <your-own-email>. When it comes back
Acknowledge, set the item Status to "In Progress".

P2: send a Teams chat from the Flow bot to the assigned owner.
P3 (default): send an email to the assigned owner.

Re-validate and preflight.
```

> **Note:** you are assigning the approval to **yourself** so you can drive your own demo. The
> *assignment* still comes from the routing table — that is the data-driven part.

### Prompt 4 — the SLA timer (the part nobody builds by hand)

```
Add a second branch that runs in PARALLEL with the Switch, starting from the
update action — not after the Switch.

It should wait until one minute before DueBy, then re-read the item. If the item's
Status/Value is not "In Progress" and not "Closed", set Status to "Escalated",
increment EscalationCount, and post a message to IT-Ops naming the routing row's
EscalationEmail and the request title.
```

### Prompt 5 — production hardening

```
Wrap everything in a scope called "Triage". Add a second scope "Handle failure"
configured to run only when Triage has failed or timed out. It should filter
result('Triage') for failed actions, post the failing action name and error message
to IT-Ops, then terminate the flow as Failed.

Validate, preflight, create, and publish. Then confirm with list_flows that the
state is actually Started.
```

> **`result('Triage')`** is the idiom that turns *"a flow failed somewhere"* into *"action X
> failed with message Y"*. It is the single most useful thing in this flow and it takes one
> sentence to ask for.
>
> **And note the last line.** `publish_flow` can return `{"success": true}` while activation
> actually failed — the real error appears only in the server log. **Always confirm with
> `list_flows`.**

### Prompt 6 — prove it

```
Add an item to IT-Requests with Title "[<yourname>] New laptop for contractor
onboarding", RequestType Hardware, Priority P2, Requester <a demo account>.
Then show me the run history for my flow and explain what each action returned.
```

> ### ⏱️ Expect to wait — this is normal, not a bug
> A newly activated SharePoint trigger can take **up to an hour** to fire the **first** time.
> Measured in the reference build: activated 15:25, first run 16:24 — **59 minutes**. After that
> it polls on schedule.
>
> **Do not start "fixing" a working flow.** If you see no run, check how long ago you activated.
> This is why we activate before the break.

**What a healthy run looks like:**

| Action | Status | What it proves |
|---|---|---|
| `Compose_routing` | Succeeded | The routing lookup matched |
| `Assign_the_request` | Succeeded | Item updated |
| `Chat_the_owner` | Succeeded | P2 branch fired |
| `Email_the_owner` | **Skipped** | ✅ the Switch matched `P2` — it did **not** fall through |

That **Skipped** row is the important one. Verifying the branches that should do *nothing* is
what proves your routing, not the green tick.

## 3.5 The staged failure — the best 10 minutes of the day

`Routing-Table` has **no `Incident` row**. On purpose.

```
Add an item to IT-Requests with Title "[<yourname>] Mail relay dropping outbound
messages", RequestType Incident, Priority P1.
```

The routing lookup returns an empty array, `value[0]` fails, and your failure scope reports it
to IT-Ops. Now debug it **with the agent**:

```
/debug-flow
```

or, for the autonomous version:

```
My flow just failed. Get the run history, find the failing action, explain the root
cause, and fix the flow so an unmatched RequestType falls back to a DEFAULT routing
row and posts a warning instead of failing.
```

Try **`/diagnose-flow`** too — it classifies each failed action with a remediation rather than
walking you through interactively.

**This is the moment the room understands:** the agent is a debugger, not just a generator. It
read a real run, found the failing action, and repaired the definition.

## 3.6 Troubleshooting — Scenario 1

| Symptom | Cause | Fix |
|---|---|---|
| `validate_flow` says `extra-authentication` | `$authentication` in an **action** | It belongs on the **trigger only** — the Flow API injects it into actions |
| Save fails: `missing required property 'item/Title'` | `PatchItem` without Title | Send `item/Title` on **every** update, even a status-only one |
| Every request takes the P3 email branch | Reading `Priority` not `Priority/Value` | Choice columns are objects |
| Escalation fires immediately | Delay offset larger than the SLA | With minute-scale SLAs use `addMinutes(DueBy, -1)`, not minus 1 hour |
| Flow saved but state is `Stopped` | `publish_flow` false success | Re-publish; confirm with `list_flows`; read the server log |
| No runs at all | First-poll latency | Wait up to an hour; check the trigger is `GetOnNewItems` |
| Run history looks stale | Nothing new was **created** | The trigger fires on **create** only. Editing a row does nothing. |

---

# Part 4 — Break (1:30–1:40)

**Leave your flow Started.** The first-poll latency means your flow will be warm when you return.

---

# Part 5 — Scenario 2 — Flow Health Guardian (1:40–2:40)

> *"You have 60 flows in production. Who is watching them? Nobody. Let's fix that in 15 minutes."*

## 5.1 The business case

Power Automate's built-in failure notification is per-owner, per-flow, easy to ignore, and gives
you no cross-tenant view. Silent failures get discovered days later by an angry business user.

This flow is an **automated ops standup for your automation estate**: it inventories failed runs,
classifies them, logs them, and posts one digest to the ops channel.

## 5.2 What you will learn

**About flows:** the Dataverse `flowruns` table, array filtering, classification with nested
expressions, `Apply to each` with concurrency control, and a zero-state branch.

**About building with the agent — and this is the real lesson:** what to do when the connector
**cannot do what you need**.

## 5.3 Start by discovering a dead end (do not skip this)

```
Show me every operation the Power Automate Management connector exposes for listing
flows, listing flow runs, and resubmitting a run. Give me exact operation IDs.

Is there any operation that can LIST flow runs? If not, say so explicitly — do not
substitute a similar-sounding one. Don't build anything yet.
```

**Expected answer: there is no list-runs operation.** All 24 operations were enumerated during
the build. `ResubmitFlow` and `CancelFlowRun` both require a `runId` **you must already have** —
the connector can *remediate* a run but cannot *discover* one.

The original lab design was built on that non-existent operation. It took one read-only prompt
to find out.

> ### 💡 The most transferable idea in this lab
> The agent reported the gap instead of inventing an operation — exactly the behaviour you want.
> The failure mode to fear is the model that cheerfully writes `ListFlowRuns` into the
> definition, saves it, and hands you something that dies at runtime.
>
> **But "this connector can't" is not "this can't be done."** Ask the follow-up question:

```
Flow runs must be recorded somewhere. Is there a Dataverse table that holds flow run
history? Show me its columns.
```

**Answer: the `flowruns` table** — `status`, `errorcode`, `errormessage`, `starttime`,
`_workflow_value`, 28-day retention — queryable with the **Standard-tier Dataverse connector**.

This is *better* than the original design: one flat, server-filtered query instead of
*list flows → for each flow → list its runs*, an N+1 pattern that falls over at 500 flows.

## 5.4 The prompt ladder

### Prompt 1 — the spine

```
Create a flow "HOL S2 — Flow Health Guardian — <yourname>" in this environment.

Trigger: recurrence every 15 minutes.
Use the Dataverse connector to list rows from the flowruns table, filtered to
status eq 'Failed' and starttime greater than 24 hours ago. Select name, status,
errorcode, errormessage, starttime, _workflow_value and resourceid. Order by
starttime descending, top 50.

Validate and preflight. Do not publish yet.
```

### Prompt 2 — do not let it eat itself

```
Add a filter that excludes this flow's own runs, comparing each row's resourceid to
workflow()?['name']. Also filter to only the flows whose name ends with "<yourname>"
so I only see my own failures in this shared environment.
```

> **Both filters are mandatory here, not optional.** On a 15-minute recurrence the Guardian
> appears in its own inventory, logs itself, and — once resubmit is wired in — can resubmit
> itself. And in a shared environment without the name filter, you will be looking at twenty
> people's failures.

### Prompt 3 — classification and logging

```
For each failed run, compute a classification:
- Transient if the error code is 429, 500, 502, 503 or 504, or the message contains
  "timeout" or "throttl"
- Structural if the code is 400, 401, 403 or 404, or the message contains
  "connection" or "expired"
- otherwise Unknown

Create an item in the SharePoint list Flow-Health-Log with the flow id, run id,
error code, error message, run start time and classification. Set Status to
"Resubmitted" for Transient, "Escalated" for Structural, "Failed" for Unknown.
Set the loop concurrency to 1.
```

### Prompt 4 — do not build a retry storm

```
Before logging a run, check Flow-Health-Log for an item with the same RunId. If one
already exists, skip that run entirely.
```

> ### ⚠️ This is a correctness fix, not a nicety — confirmed live
> During the reference build the Guardian ran unattended for ~6 hours. `Flow-Health-Log`
> ended up with **25 rows for exactly one failed run** — it re-logs the same failure on every
> cycle, because it queries a rolling 24-hour window with no memory of what it already wrote.
>
> ```
> total rows: 25   distinct RunIds: 1
>   08584152156028960900548418611CU10  logged 25x
> ```
>
> With a resubmit step wired in, that would have been **25 resubmits of a failing run**.
> *The agent will happily build the footgun if you ask for one.*

### Prompt 5 — the digest

```
After the loop, post one adaptive card to the Teams channel IT-Ops with the total
failed runs, how many were resubmitted, how many escalated, and the number of
distinct flows affected. If there were zero failures, post a short "all healthy"
message instead.

Wrap it all in a scope with a failure handler that reports to IT-Ops.
Validate, preflight, create and publish, then confirm the state with list_flows.
```

### Prompt 6 — prove it

```
Trigger this flow now and show me the run history. Then show me the items it created
in Flow-Health-Log.
```

You can also use the **`manage-flows`** skill for lifecycle operations:

```
/manage-flows
```

## 5.5 The showstopper

Run it against the canary flows the facilitator broke this morning. The room sees three broken
flows discovered, classified, logged, and a Teams card — from five sentences of English.

Then the line:

> *"This flow monitors every flow in the environment — including itself. Which is exactly why we
> had to teach it not to."*

**And a true story from the build:** the Guardian caught **Scenario 3's failure** while we were
still writing Scenario 3. Not a canary — a real bug, in another lab flow, found by the flow
whose entire premise is watching other flows.

## 5.6 Troubleshooting — Scenario 2

| Symptom | Cause | Fix |
|---|---|---|
| Agent proposes "List Flow Runs" | It guessed | That operation does not exist. Point it at Dataverse `flowruns`. |
| Empty digest every time | No failed runs in the window | The canaries must have failed in the **last 24 h**. Re-run them. |
| Guardian logs itself | Self-exclusion filter missing | Compare `resourceid` to `workflow()?['name']` |
| You see other people's failures | Name filter missing | Filter to flows whose name ends with your suffix |
| Same run logged repeatedly | No dedupe | Add the `RunId` lookup from Prompt 4 |
| `flowruns` query returns nothing | Wrong filter syntax on `starttime` | Ask the agent to `get_expression_help` for date filtering |

---

# Part 6 — Scenario 3 — Self-Service Access Provisioner (2:40–3:05)

> *"The access request that provisions itself — with an approver, an audit trail, and a rollback date."*

## 6.1 The business case

*"Please add me to the Marketing group."* Today: a ticket, a human, a copy-paste, and **no
expiry**. Access granted for a two-week project is still there two years later. This flow closes
the loop and **auto-revokes**.

## 6.2 What you will learn

- **Two-stage conditional approval** — manager for standard groups, security owner for privileged
- **Writing to Entra** from a flow, with a real, verifiable state change
- **Time-bound access with automatic revocation** — a genuine compliance win
- **That a parameter's name is not its contract** — the sharpest lesson of the day

## 6.3 The prompt ladder

### Prompt 1 — confirm the tools exist

```
I need to add and remove Entra group members from a flow. Show me which connector
can do that and its exact operation IDs. Confirm the connection exists and is
Connected — if it is not, stop and tell me.
```

**Expected:** the **Microsoft Entra ID** connector (`shared_azuread`, **Standard** tier) with
`AddUserToGroup` and `RemoveMemberFromGroup`.

> Note what you did **not** need: the premium *HTTP with Microsoft Entra ID* connector and
> hand-written Graph URLs. The first attempt in the reference build went down that road
> unnecessarily. Always ask what the connector surface already offers.

### Prompt 2 — approvals

```
Create a flow "HOL S3 — Access Request Provisioner — <yourname>".

Trigger on item created in Access-Requests. Look up the item's TargetGroup/Value in
Privileged-Groups to get GroupId, IsPrivileged and SecurityOwnerEmail. Get the
requester's manager with Office 365 Users.

Start an approval assigned to the manager. If the outcome is not Approve, set Status
to "Rejected", notify IT-Ops, and terminate.

Validate and preflight. Do not publish.
```

### Prompt 3 — the privileged path

```
If the matched group's IsPrivileged is true — it is a real boolean, compare to true,
not to the string "Yes" — add a second approval assigned to SecurityOwnerEmail, with
the same rejection path.

Both rejection paths must terminate BEFORE any Entra call.
```

> **Ordering matters and it is a compliance question, not a style one.** *"It approved correctly
> but provisioned anyway"* is an audit finding. Later you will verify that both reject branches
> show **Skipped** on the happy path.

### Prompt 4 — provision

```
On full approval, resolve the requester's Entra object id with Office 365 Users, then
add them to the group with the Microsoft Entra ID connector.

Check the connector's swagger for what the user-id parameter actually expects before
you build it — do not assume it takes a Graph URL. Connector object parameters use
slash-flattened keys, so it is body/@odata.id, not a nested body object.

Then set Status to "Provisioned", GrantedOn to utcNow(), and
ExpiresOn to utcNow() plus DurationMinutes. Use addMinutes with an integer.
```

> ### 🔍 The trap this prompt defuses
> `AddUserToGroup` has a parameter named **`@odata.id`**. In the raw Graph API that key takes a
> full URL: `https://graph.microsoft.com/v1.0/directoryObjects/{id}`.
>
> **The connector wants a bare GUID.** It builds the URL itself. Pass the URL and it wraps a URL
> in a URL, and Graph returns:
>
> ```
> Request_BadRequest: Unexpected segment DynamicPathSegment. Expected property/$value.
> ```
>
> It saved. It published. It passed `validate_flow` **and** `preflight_flow`. It failed only when
> a real run hit it. The only source of truth was the connector's swagger, where
> `x-ms-summary` reads `"User Id"` and the example is a bare GUID.
>
> **A green preflight proves your definition is well-formed, not that it is right.**

### Prompt 5 — revoke

```
After ExpiresOn, remove the member from the group and set Status to "Revoked", then
notify. Wrap everything in a scope with a failure handler that reports to IT-Ops.
Validate, preflight, create, publish, and confirm with list_flows.
```

### Prompt 6 — prove it end to end

```
Add an item to Access-Requests: Title "[<yourname>] Falcon access", Requester
<demo account>, TargetGroup "HOL-Project Falcon", DurationMinutes 5, Status Pending.
Then watch the run.
```

Approve when it arrives. Then verify **independently in Entra** that the member appears — and
five minutes later, that they are gone. Do not trust the flow's own status field; that is the
whole point of an audit trail.

## 6.4 The honest closing point

> *"`Delay Until` holds a flow instance open for the whole duration. For five minutes that is
> fine. For 90 days it is not — you'd move revocation to a nightly sweep over items past
> `ExpiresOn`. The agent will build whichever one you ask for. Knowing which one to ask for is
> still your job."*

## 6.5 Troubleshooting — Scenario 3

| Symptom | Cause | Fix |
|---|---|---|
| `Unexpected segment DynamicPathSegment` | Full Graph URL passed to `@odata.id` | Pass a **bare user GUID** |
| Save fails: `missing required property 'body/@odata.id'` | Body sent as nested JSON | Use the flattened key `body/@odata.id` |
| Approval never arrives | Requester has no manager | Check in Entra; a null approver fails silently |
| Privileged group takes only one approval | `IsPrivileged` compared as a string | It is a boolean — compare to `true` |
| Member added despite rejection | Reject branch downstream of the Entra call | Reorder — terminate before provisioning |
| `InvalidApprovalType` | Guessed the enum | It is `CustomResponse`, singular. Use `invoke_operation` → `GetApprovalTypes` |
| Graph returns 404 on the group | Placeholder or dynamic group | Use the real object ID; dynamic-membership groups reject manual writes |

---

# Part 7 — Package what you built (3:05–3:12)

Your flows are not artefacts in a portal — they are code you can promote.

```
/manage-flows
```

Then:

```
Give me an inventory of the flows I own in this environment, with their state and
last modified time.
```

## Exporting as a solution

In `make.powerautomate.com` → **Solutions** → **New solution** → add your three flows via
**Add existing → Cloud flow**.

**Then add your connection references too** — `Add existing → Connection reference`.

> ### Why connection references, and why *not* connections
> A solution containing only flows exports with **zero connection bindings** — verified during
> the build. On import, nothing can be mapped.
>
> **Connections** are per-user, per-environment credentials and are deliberately *not* solution
> components. **Connection references** are the portable abstraction: the importer prompts you to
> bind each one to a real connection in the target environment.
>
> SharePoint lists, Teams channels and Entra groups are **not** solution components either.
> Recreate them in the target and re-point the GUIDs.

**Export → Unmanaged → download the zip.** Compare it to `KTHandsOn_1_0_0_0.zip` in your folder.

**The honest weak point:** SharePoint list GUIDs, the Teams channel ID and Entra group IDs are
baked into the definitions. Promoting properly means moving them into **environment variables** —
that is the natural L400 follow-on.

---

# Part 8 — Debrief (3:12–3:15)

## The failure taxonomy — every one of these actually happened

| Failure | The signal | The fix |
|---|---|---|
| Agent writes ARM / uses `az` for a flow task | Zero MCP tool calls; talk of resource groups | **Stop it.** Logic Apps ≠ Power Automate. Re-pin the model. |
| Auto-mode picked a weak model | 56 tools loaded, none invoked | `/model`. Highest-impact fix there is. |
| "Proceeding now…" for minutes | Narration without tool calls | **Esc.** Restate the guardrail. |
| Invented operation ID or enum | `ApiOperationNotFound`, `InvalidApprovalType` | Look it up. 4 of 4 guesses were wrong. |
| Value looks right, fails at runtime | Green preflight, `BadRequest` on run | Read the connector swagger. |
| No runs after activation | Empty run history | First poll can take an hour. Wait before diagnosing. |
| "The connector can't do it" | A missing operation | Ask *where else does this data live?* |

## The build-cycle number worth remembering

| Flow | Build cycles to green |
|---|---|
| Scenario 1 | **6** |
| Scenario 2 | **0** |
| Scenario 3 | **2** |

Scenario 2 was built first-try — because every failure from Scenario 1 was applied before writing
a line of it. **The errors are the curriculum.** Sequence your own work the same way.

## The closing frame

The MCP server does not replace flow knowledge — **it removes the clicking.** You still need to
know that `Delay Until` holds an instance open, that `Apply to each` hits throttling limits, that
retries need a cap, and that approvals must precede writes.

What changed is the cost of trying. Building a flow, running it, reading the failure, and fixing
it is now a five-minute loop instead of a forty-minute one. That is what makes the debugging
skill worth having.

---

# Appendix A — Troubleshooting reference

## Setup and plugin

| Error | Meaning | Fix |
|---|---|---|
| `Marketplace … already registered` | Harmless | Skip `add`, run `install` |
| `Access is denied. (os error 5)` | **File lock**, not permissions | Close every Copilot CLI / VS Code window. Admin does **not** help. |
| `ServiceToServiceEnvironmentNotFound` | Wrong tenant in FlowAgent's own cache | Set `PA_TENANT_ID`; clear `%LOCALAPPDATA%\flowagent\msal-cache` and `\tokens` |
| `No environment specified and no default set` | Env pin lost between processes | `set_current_env` again, or set `PA_DEFAULT_ENVIRONMENT` |
| Tools not appearing | Plugin not loaded | Restart the CLI after install |

## Save-time errors

| Error | Fix |
|---|---|
| `extra-authentication` | `$authentication` belongs on the **trigger only** |
| `missing required property 'item/Title'` | Send `item/Title` on every `PatchItem` |
| `missing required property 'body/@odata.id'` | Use `/`-flattened keys, not nested JSON |
| `ApiOperationNotFound` | Guessed operation ID — use `search_operations` |
| `InvalidApprovalType` | `CustomResponse`, singular |
| `connection reference … could not be found` | `update_flow` on a solution flow — delete and recreate instead |

## Runtime errors

| Error | Fix |
|---|---|
| `Unexpected segment DynamicPathSegment` | Bare GUID, not a Graph URL |
| Expression fails on `addMinutes`/`addDays` | Arguments must be **integers** |
| Switch always hits default | Read Choice columns as `.../Value` |
| Empty array index | Guard the lookup — add a DEFAULT fallback row |

## Behavioural

| Symptom | Fix |
|---|---|
| `publish_flow` says success, state is `Stopped` | Confirm with `list_flows`; read the server log |
| Flow is `Started` but never runs | Up to 1 h first-poll latency; and the trigger fires on **create** only |
| Agent narrates without acting | **Esc**, restate the guardrail prompt |

---

# Appendix B — Skills reference

Invoke with a slash command in the Copilot CLI.

| Skill | Use it when | You use it today in |
|---|---|---|
| `/setup` | First-time prerequisites, or something is broken | Part 1.7 |
| `/browse-flows` | Explore environments and flows | Part 2.2 |
| `/create-flow` | Guided, interactive flow creation | Scenario 1 |
| `/build-flow` | Autonomous build from a description | Scenario 2 |
| `/debug-flow` | Interactive debug of a failed run | Scenario 1 staged failure |
| `/diagnose-flow` | Autonomous deep diagnosis of a run | Scenario 1 staged failure |
| `/manage-flows` | Publish, test, batch ops, inventory | Part 7 |
| `/manage-desktop-flows` | Desktop / RPA flows and machine groups | not today |
| `/route-environments` | Environment resolution and routing | if your env is wrong |

**Under the skills sit 56 MCP tools.** The ones worth knowing by name:

| Tool | What it does |
|---|---|
| `set_current_env` | Pin the environment for this session |
| `pick_or_create_connection` | Idempotently get a Connected connection |
| `resolve_entity` | Display name → GUID, with a confidence score |
| `list_datasets` / `list_tables` | SharePoint sites and lists |
| `search_operations` / `get_connector` | Find real operation IDs |
| `resolve_params` | Exact parameter names for an operation |
| `invoke_operation` | Call a connector's dynamic resolver (e.g. valid enum values) |
| `validate_flow` / `preflight_flow` | Catch errors before saving |
| `create_flow` / `publish_flow` | Create and activate |
| `get_run_history` / `get_run_actions` / `diagnose_run` | Read what happened |
| `edit_flow` | Surgical edits without resending the whole definition |
| `get_expression_help` | Look up Power Automate expression functions |

---

# Appendix C — Your environment card

**Fill this in during Part 1. You will use it all day.**

| Item | Value |
|---|---|
| **My name suffix** | `_______________________` |
| Tenant ID | `_______________________` |
| Environment name | `_______________________` |
| Environment ID | `_______________________` |
| SharePoint site URL | `_______________________` |
| Teams team `Contoso` groupId | `_______________________` |
| Teams channel `IT-Ops` channelId | `_______________________` |
| My email (for approvals) | `_______________________` |
| My assigned demo requester | `_______________________` |

**SharePoint list GUIDs** *(from `resolve` in Part 2.3, or the xlsx `Environment-Reference` sheet)*

| List | GUID |
|---|---|
| IT-Requests | `_______________________` |
| Routing-Table | `_______________________` |
| Flow-Health-Log | `_______________________` |
| Privileged-Groups | `_______________________` |
| Access-Requests | `_______________________` |

**My flows**

| Scenario | Flow name | Flow ID | State |
|---|---|---|---|
| S1 | HOL S1 — IT Request Triage — ______ | ____________ | ______ |
| S2 | HOL S2 — Flow Health Guardian — ______ | ____________ | ______ |
| S3 | HOL S3 — Access Request Provisioner — ______ | ____________ | ______ |

---

### Two things to take back to work

1. **Pin your model, and paste the guardrail prompt.** Everything else is recoverable.
2. **Ask the agent to tell you when something does not exist**, rather than substituting the
   closest match. One sentence; it is the cheapest protection you have against a flow that saves
   cleanly and dies in production.
