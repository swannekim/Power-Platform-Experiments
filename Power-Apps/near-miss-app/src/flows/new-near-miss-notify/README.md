# Flow: New near-miss → notify + create action

**Trigger:** Dataverse — *When a row is added* to **Near-Miss Reports**.
**Actions:** notify the EHS reviewer in Teams; create a starter **Corrective Action** row linked to the report.

`definition.json` is the Logic-Apps-style flow definition for reference. To use it: recreate the flow in the
maker portal (fastest, connections bind cleanly), or import it as a **solution cloud flow** and fix the
connection references.

## Companion flows (in this folder's siblings)
- [`../overdue-action-escalation`](../overdue-action-escalation) — daily: mark overdue actions, notify owners.
- [`../weekly-digest`](../weekly-digest) — Monday: post a weekly safety digest to a Teams channel.

See `../README.md` for the full index and the companion `.docx` for the narrative.
