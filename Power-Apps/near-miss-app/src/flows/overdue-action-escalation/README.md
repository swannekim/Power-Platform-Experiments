# Flow: Overdue-action escalation

**Trigger:** Recurrence — daily at 08:00 **Korea Standard Time**.
**What it does:**
1. Lists **Corrective Actions** whose `nm_duedate` is in the past and whose status is *Open* or *In progress*
   (expanding the owner's email and the parent near-miss title).
2. For each, sets status to **Overdue** and posts a Teams DM to the **owner** (falling back to the manager if
   the owner has no email).
3. Posts a one-line daily summary to the **manager**.

## Bind before you run
- `managerEmail` parameter → a solution **environment variable** (don't hard-code).
- Choice values used: `nm_actionstatus` Open = `100000000`, In progress = `100000001`, Overdue = `100000003`
  (from `src/solution/src/Customizations.xml` — adjust if you changed them).

## How to use
Recreate in the maker portal (fastest — connections bind cleanly) or import as a solution cloud flow and fix
the two connection references (`shared_commondataserviceforapps`, `shared_teams`). Operation IDs / parameter
paths are the exported shapes and may re-bind on import.
