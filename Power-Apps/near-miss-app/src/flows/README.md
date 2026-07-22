# Power Automate flows

Three cloud flows for the Near-Miss Safety solution. Each folder has a `definition.json` (Logic-Apps-style
export shape, for reference/import) and a `README.md`. Fastest path: recreate in the maker portal so
connections bind cleanly; alternatively import as **solution cloud flows** and fix connection references.
Parameters marked "bind to an environment variable" should be solution environment variables, not hard-coded.

| Flow | Trigger | Purpose |
|------|---------|---------|
| [`new-near-miss-notify`](./new-near-miss-notify) | Dataverse row added | Notify EHS reviewer + create a starter corrective action |
| [`overdue-action-escalation`](./overdue-action-escalation) | Daily 08:00 KST | Mark overdue actions, notify owners, summarise to manager |
| [`weekly-digest`](./weekly-digest) | Monday 08:00 KST | Post a weekly safety digest to a Teams channel |

Choice values referenced by the filters live in `../solution/src/Customizations.xml`.
