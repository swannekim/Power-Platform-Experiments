# Power Platform Custom Connector – Code‑First Guide
This repository demonstrates how to build production‑ready, code‑first Custom Connectors for Microsoft Power Platform (Power Automate, Power Apps, Logic Apps, Copilot Studio) using OpenAPI (Swagger) as the source of truth.

It reflects practical patterns and lessons learned from real Power Platform integrations and is intentionally not an official Microsoft repository.

---

## What is a Custom Connector?
> [MS Learn: Custom connectors overview](https://learn.microsoft.com/en-us/connectors/custom-connectors/)

A Custom Connector lets Power Platform securely call any REST (or SOAP) API that is not available as a built‑in connector.

According to Microsoft Learn, a custom connector is:
- A wrapper around a REST API
- Exposed as triggers and actions across Power Automate, Power Apps, Logic Apps, and Copilot Studio
- Shareable across environments and solutions

This repository focuses on code‑based (OpenAPI‑driven) custom connectors, not click‑only UI creation.

---

## When You Should (and Should Not) Use Custom Connectors

### ✅ Good fit
- APIs reused across multiple flows or apps
- Internal or proprietary enterprise APIs
- Scenarios requiring governance, discoverability, and reuse
- Stable, versioned API contracts

### ❌ Not a good fit

- Built‑in connector already meets requirements
- One‑off API calls → consider the HTTP action instead
- Rapidly changing or undocumented APIs
- Custom connectors shine when you treat them as products, not shortcuts.

---

## Why Code‑First?

| UI-only Connector | Code-First Connector |
| ----------------- | -------------------- |
| Fast to start     | Scales across teams  |
| Hard to version   | Git-friendly         |
| Manual updates    | Reproducible builds  |
| Limited reuse     | Environment-portable |

Microsoft Learn strongly encourages defining APIs explicitly and managing them across environments and solutions.

---

## Connector Lifecycle (Microsoft‑Defined)
From the official lifecycle:

1. Build your API (public or private)
2. Secure your API (Microsoft Entra ID recommended)
3. Define the connector (OpenAPI, Postman, or blank)
4. Test and share the connector
5. Package in solutions for ALM and CI/CD

This repo focuses on steps 3–5, assuming an existing API.

---

## Core Principle: OpenAPI as the Source of Truth
> [MS Learn: Create a custom connector from an OpenAPI definition](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-openapi-definition)

Everything starts from OpenAPI (Swagger 2.0).

The OpenAPI definition controls:
- Endpoints and parameters
- Request and response schemas
- Authentication metadata
- Action names shown in designers

⚠️ Power Platform currently supports OpenAPI 2.0 only. (Mar 2026)

### Minimal OpenAPI Example
```yaml
swagger: '2.0'
info:
  title: Sample Custom Connector
  description: Code‑first Power Platform custom connector
  version: '1.0'
host: api.example.com
schemes:
  - https
paths:
  /status:
    get:
      operationId: GetStatus
      summary: Get API status
      responses:
        200:
          description: OK
          schema:
            type: object
            properties:
              status:
                type: string
```

#### Why these fields matter

- `operationId` → Action name in Power Automate
- `summary` → What makers see in the designer
- `schema` → Enables reliable dynamic content

---

## Authentication Options
Microsoft‑supported authentication types include:
- API Key
- Basic Authentication
- OAuth 2.0 (Generic or Microsoft Entra ID)

### OAuth 2.0 (Recommended)
For enterprise APIs, Microsoft recommends Microsoft Entra ID (Azure AD) authentication.

Typical setup:
- App registration for the API
- App registration for the Custom Connector
- Per‑connector redirect URI (mandatory for OAuth connectors)

---

## Writing Code in a Custom Connector
> [MS Learn: Write a Code in Custom Connector](https://learn.microsoft.com/en-us/connectors/custom-connectors/write-code)
> [MS Learn: Create a custom connector from scratch](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-blank)

Power Platform allows **C# code** to transform requests and responses beyond declarative policies.

Key points from Microsoft Learn:
- Code must implement a Script class
- `ExecuteAsync()` is the runtime entry point
- Code takes precedence over codeless definitions
- The class name must be `Script` and it must implement `ScriptBase`

    ```C#
    public class Script : ScriptBase
    {
        public override Task<HttpResponseMessage> ExecuteAsync()
        {
            // Your code here
        }
    }
    ```

Common use cases:
- Payload reshaping
- Custom headers
- Regex or transformation logic

---

### Creating the Connector
You can create custom connectors by:

- Importing an OpenAPI file
- Importing a Postman collection
- Creating from blank using the wizard

Your code MUST:
- Be written in C#
- Have a maximum execution time of five seconds
- Have a file size no larger than 1 MB

[🏗️ How to Create Custom Connector: Example with Screenshots](Power-Automate/Custom-Connector/example/README.md)

Creating from blank is useful for learning, but OpenAPI import is recommended for production.

---

### Using Solutions (ALM)
Microsoft Learn recommends creating custom connectors inside solutions to:

- Move connectors across environments
- Enable CI/CD and versioning
- Package flows, apps, and connectors together

Treat connectors as deployable assets.

---

## Common Pitfalls

- Missing operationId
- Using OpenAPI 3.0 definitions
- Weak or incorrect response schemas
- OAuth scope or redirect URI mismatches

Treat your OpenAPI like production code.

---

*Happy building* 🚀
