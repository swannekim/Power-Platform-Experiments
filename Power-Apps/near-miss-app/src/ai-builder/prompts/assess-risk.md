# Prompt: Assess risk

**Where:** AI hub → Prompts → *Create a prompt*. Save into the solution.
**Purpose:** suggest a risk level with a one-line rationale. The human sets severity & likelihood; AI advises.

## Inputs
| Name | Type | Bound to (canvas) |
|------|------|-------------------|
| `description` | Text | `txtDescription.Text` |
| `severity` | Text | `drpSeverity.Selected.Value` (1–5) |
| `likelihood` | Text | `drpLikelihood.Selected.Value` (1–5) |

## Prompt instruction

```
You are a safety risk assessor. Given a near-miss description and the reporter's
severity (1-5) and likelihood (1-5) ratings, return ONLY:

RiskLevel: one of [Low, Medium, High, Critical]
Rationale: one short sentence.

Guidance: Critical if severity>=4 and likelihood>=4; High if the product of
severity*likelihood >= 12; Medium if >= 6; otherwise Low. Reply in the same
language as the description.

Description: {description}
Severity: {severity}
Likelihood: {likelihood}
```

## Consume in Power Fx
```powerapps
Set(
    varRisk,
    'Assess risk'.Predict({
        description: txtDescription.Text,
        severity:    drpSeverity.Selected.Value,
        likelihood:  drpLikelihood.Selected.Value
    })
);
UpdateContext({ ctxRisk: varRisk.Text });
```
