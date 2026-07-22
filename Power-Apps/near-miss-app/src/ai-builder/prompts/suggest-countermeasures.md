# Prompt: Suggest countermeasures

**Where:** AI hub → Prompts → *Create a prompt*. Save into the solution.
**Purpose:** 2–4 concrete preventive actions, informed by similar past incidents (RAG-lite).

## Inputs
| Name | Type | Bound to (canvas) |
|------|------|-------------------|
| `incidentDescription` | Text | `txtDescription.Text` |
| `similarIncidents` | Text | concatenated text of similar past reports (see below), or "" |

## Prompt instruction

```
Propose 2 to 4 concrete, practical preventive actions for the near-miss below.
Prefer engineering and procedural controls over "be more careful". If similar
past incidents are provided, learn from their countermeasures and avoid
repeating ones that clearly failed. Return a short numbered list only, in the
same language as the description.

Near-miss: {incidentDescription}
Similar past incidents: {similarIncidents}
```

## Building `similarIncidents` in Power Fx (optional but recommended)
```powerapps
// Naive similarity: recent reports sharing the drafted category.
Set(
    varSimilar,
    Concat(
        FirstN(
            Sort(
                Filter('Near-Miss Reports', Category.Value = ctxCategory),
                'Observed on', Descending
            ),
            5
        ),
        Title & ": " & 'Immediate action taken' & Char(10)
    )
);
Set(
    varCounter,
    'Suggest countermeasures'.Predict({
        incidentDescription: txtDescription.Text,
        similarIncidents:    varSimilar
    })
);
UpdateContext({ ctxCountermeasure: varCounter.Text });
```
