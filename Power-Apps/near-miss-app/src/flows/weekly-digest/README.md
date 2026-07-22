# Flow: Weekly digest

**Trigger:** Recurrence — weekly, **Monday 08:00 Korea Standard Time**.
**What it does:**
1. Lists **new near-miss reports** from the last 7 days and all **open/overdue corrective actions**.
2. Uses *Filter array* to count **High/Critical** new reports and **overdue** actions.
3. Composes an HTML digest (counts + a bulleted list of the new reports with their risk level).
4. Posts it to a **safety Teams channel**.

## Bind before you run
- `teamId` and `channelId` parameters → solution **environment variables** for your safety channel.
- Choice values referenced (from `src/solution/src/Customizations.xml`):
  - `nm_risklevel`: High = `100000002`, Critical = `100000003`
  - `nm_actionstatus`: Open = `100000000`, In progress = `100000001`, Overdue = `100000003`

## How to use
Recreate in the maker portal or import as a solution cloud flow. The channel-post operation
(`PostMessageToConversation` with `location: Channel`) re-binds to the modern *Post message in a chat or
channel* action when you open it in the designer — pick your team + channel there. The `&#8226;` in the
*Select* is the bullet character used to build each line.
