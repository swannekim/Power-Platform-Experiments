# Canvas app source

Mobile-first field-reporting app. These files capture the **control hierarchy and Power Fx** for each screen
in the Power Apps YAML source style (as produced by `pac canvas`). Two ways to use them:

1. **Studio-first (simplest):** create a blank Tablet/Phone canvas app in the solution, turn on
   **modern controls & themes**, add the controls listed here, and paste the Power Fx into the matching
   properties (`OnStart`, `OnSelect`, `Items`, etc.).
2. **CLI:** `pac canvas` can unpack/pack `.msapp` to/from YAML. Start from a blank app you author in Studio,
   then keep these files as your source of truth under version control.

> Control template versions in `pac canvas` YAML are pinned per Studio release, so a hand-written `.msapp`
> won't always pack cleanly across versions. Treat these as the **authoritative logic**; let Studio own the
> exact control/version metadata.

## Data sources to add in the app
- Dataverse tables: **Near-Miss Reports**, **Corrective Actions**, **Sites**
- AI Builder prompts: **Classify near-miss**, **Assess risk**, **Suggest countermeasures**, **Translate**
- (Optional) Office 365 Users, the Copilot Studio agent (for the Assistant screen)

## Screens
| File | Screen | Purpose |
|------|--------|---------|
| `App.fx.yaml` | App | Language detection, theme, seed collections |
| `screens/Home.fx.yaml` | scrHome | Entry point / navigation |
| `screens/Report.fx.yaml` | scrReport | Capture + AI assist + submit |
| `screens/MyReports.fx.yaml` | scrMyReports | Reporter's own history |
| `screens/Assistant.fx.yaml` | scrAssistant | Embedded Copilot Studio agent |
