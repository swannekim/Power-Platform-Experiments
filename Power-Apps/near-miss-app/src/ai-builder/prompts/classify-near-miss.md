# Prompt: Classify near-miss

**Where:** AI hub → Prompts → *Create a prompt* (Prompt builder). Save into the solution.
**Model:** GPT‑4o class (default).
**Purpose:** first-pass category + hazard type from a free-text description. Multilingual.

## Inputs
| Name | Type | Bound to (canvas) |
|------|------|-------------------|
| `incidentDescription` | Text | `txtDescription.Text` |

## Prompt instruction (paste this, keep the `{incidentDescription}` token)

```
You are a workplace-safety classifier. Read the near-miss description below and
return ONLY two short labels, each on its own line, no explanation:

Category: one of [Slip/Trip/Fall, Struck-by, Caught-in, Ergonomic, Chemical,
          Electrical, Fire/Explosion, Vehicle, Environmental, Other]
HazardType: a specific hazard in 2-4 words

Reply in the SAME language as the description (Korean, English or Japanese).

Description:
{incidentDescription}
```

## Expected output (example)
Input (Korean): "지게차가 후진하는데 경고음이 안 났고 작업자가 바로 뒤에 있었다."
```
Category: Vehicle
HazardType: 지게차 후진 충돌 위험
```

## Consume in Power Fx
```powerapps
Set(
    varClassify,
    'Classify near-miss'.Predict({ incidentDescription: txtDescription.Text })
);
// The two labels come back in varClassify.Text — parse or show for confirmation.
```
