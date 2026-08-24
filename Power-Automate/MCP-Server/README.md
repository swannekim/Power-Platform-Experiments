# Power Automate MCP Hands-On Lab

This folder contains the participant materials and reference packages for an L300–400
hands-on lab on building Power Automate cloud flows with GitHub Copilot CLI and the
[FlowAgent MCP server](https://github.com/microsoft/power-platform-skills/tree/main/plugins/power-automate).

## Start here

- [English participant guide](./PA-MCP-HOL-Participant-Guide.md)
- [Korean participant guide](./PA-MCP-HOL-Participant-Guide-KO.md)

The two participant guides cover the same lab in different languages.

## Folder structure

```text
MCP-Server/
├── README.md
├── PA-MCP-HOL-Participant-Guide.md
├── PA-MCP-HOL-Participant-Guide-KO.md
├── lab-resources/
│   ├── PA-HOL-Demo-Data-Pack-TEMPLATE.xlsx
│   └── Power-Automate-MCP-Server-Build-Guide-sanitized.md
├── sample-pa-flows/
│   ├── KTHandsOn_1_0_0_0.zip
│   ├── HOLS1ITRequestTriage_1_0_0_0.zip
│   ├── HOLS2FlowHealthGuardian_1_0_0_0.zip
│   └── HOLS3AccessRequestProvision_1_0_0_0.zip
├── personal-resources/    # Local only; excluded by .gitignore
└── session-history/       # Local only; excluded by .gitignore
```

Only `PA-HOL-Demo-Data-Pack-TEMPLATE.xlsx` is included in the published lab resources.
Other workbook variants remain local and are excluded by `.gitignore`.

## Included materials

### Participant guides

The English and Korean guides walk through the same setup and three scenarios:

1. SLA-aware IT request triage
2. Flow Health Guardian
3. Self-service access provisioning

### Lab resources

`lab-resources/` contains the demo data pack Excel file used for seed data and environment
references, plus an optional [sanitized guide](./lab-resources/Power-Automate-MCP-Server-Build-Guide-sanitized.md)
to setting up or forking the Power Automate MCP server.

### Sample Power Automate flows

The solution packages in `sample-pa-flows/` are reference implementations and recovery
points for the lab:

- `KTHandsOn_1_0_0_0.zip` contains all three reference flows.
- `HOLS1ITRequestTriage_1_0_0_0.zip` contains Scenario 1.
- `HOLS2FlowHealthGuardian_1_0_0_0.zip` contains Scenario 2.
- `HOLS3AccessRequestProvision_1_0_0_0.zip` contains Scenario 3.

Participants should build their own flows first and use these packages only when they need
an answer key or a recovery path.

## Privacy and source control

`personal-resources/` and `session-history/` are intentionally excluded from Git. Session
history remains local even when a sanitized copy exists, because it can still contain
operational context that is not intended for the public repository.

Before committing new materials, check them for tenant IDs, environment IDs, subscription
IDs, account information, private URLs, credentials, and other personal or deployment-specific
data.
