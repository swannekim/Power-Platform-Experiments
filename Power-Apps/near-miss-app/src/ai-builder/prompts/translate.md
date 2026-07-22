# Prompt: Translate

**Where:** AI hub → Prompts → *Create a prompt*. Save into the solution.
**Purpose:** translate report text between Korean, English and Japanese so a global EHS team can read every report.

## Inputs
| Name | Type |
|------|------|
| `text` | Text |
| `targetLanguage` | Text (e.g. "English", "Korean", "Japanese") |

## Prompt instruction

```
Translate the text below into {targetLanguage}. Preserve safety terminology and
numbers exactly. Return ONLY the translation, no preamble.

Text:
{text}
```

## Consume in Power Fx
```powerapps
Set(
    varEnglish,
    'Translate'.Predict({ text: txtDescription.Text, targetLanguage: "English" })
);
// Store both the original and the English translation on the record for search/reporting.
```
