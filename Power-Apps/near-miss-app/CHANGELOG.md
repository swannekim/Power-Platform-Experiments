# Changelog

## [1.0.0] – Modernised rebuild (2026)

Rebuild of Microsoft sample `009_AIHiyarihatApp` (2023) on the current Power Platform stack.

### Changed
- **AI calls**: Azure OpenAI over the HTTP connector → **AI Builder Prompts** (callable from Power Fx / Power Automate).
- **Assistant**: hand-wired chatbot → **Copilot Studio agent** with generative answers grounded in Dataverse incidents.
- **UI**: classic controls → **modern controls**, mobile-first canvas app.
- **Delivery**: manual managed-solution import → **`pac` / Power Platform Pipelines** on Managed Environments.
- **Language**: Japanese-only → **Korean / English / Japanese**.

### Added
- Severity × Likelihood **risk matrix** with human override.
- Closed-loop **Corrective Action (CAPA)** tracking with owners, due dates and overdue escalation.
- **Similar-incident** surfacing at reporting time.
- Photo capture + **GPT-4o vision** hazard description.
- **Power BI** safety dashboard (trends, hotspots, leading indicators).
- Review lifecycle: New → Under review → Actioned → Closed.
