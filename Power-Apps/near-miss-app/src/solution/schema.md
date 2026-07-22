# Dataverse schema (authoritative)

This is the source of truth for the data model. Create these tables in your **Dev** environment
(inside the solution), then run `pac solution export` + `pac solution unpack` to capture the full
entity XML back into `src/solution/src/`. The choices in `Customizations.xml` can be imported directly.

Publisher prefix used throughout: **`nm`**.

## Table: Near-Miss Report  (`nm_nearmissreport`)
| Display name | Logical name | Type | Notes |
|---|---|---|---|
| Title | `nm_name` | Text (primary) | short summary; may be AI-generated |
| Description | `nm_description` | Multiline text | reporter's own words |
| Description (EN) | `nm_descriptionen` | Multiline text | auto-translation for global review |
| Observed on | `nm_observedon` | DateTime | when it occurred |
| Site | `nm_site` | Lookup → Site | where |
| Department | `nm_department` | Text | |
| Category | `nm_category` | Choice → `nm_category` | AI-suggested, human-confirmed |
| Hazard type | `nm_hazardtype` | Choice → `nm_hazardtype` | |
| Severity | `nm_severity` | Choice → `nm_severity` (1–5) | potential consequence |
| Likelihood | `nm_likelihood` | Choice → `nm_likelihood` (1–5) | chance of recurrence |
| Risk score | `nm_riskscore` | Calculated (Whole number) | severity value × likelihood value |
| Risk level | `nm_risklevel` | Choice → `nm_risklevel` | Low/Medium/High/Critical |
| Immediate action taken | `nm_immediateaction` | Multiline text | |
| Photo | `nm_photo` | Image (or File) | optional hazard photo |
| Reporter | `nm_reporter` | Lookup → User (systemuser) | defaults to `User()` |
| Status | `nm_status` | Choice → `nm_status` | New/Under review/Actioned/Closed |
| Language | `nm_language` | Choice → `nm_language` | ko / en / ja |

## Table: Corrective Action  (`nm_correctiveaction`)
| Display name | Logical name | Type | Notes |
|---|---|---|---|
| Action | `nm_name` | Text (primary) | what will be done |
| Near-Miss Report | `nm_nearmissreport` | Lookup → Near-Miss Report | parent (N:1) |
| Owner | `nm_owner` | Lookup → User | accountable person |
| Due date | `nm_duedate` | Date only | |
| Status | `nm_actionstatus` | Choice → `nm_actionstatus` | Open/In progress/Done/Overdue |
| Resolution notes | `nm_resolutionnotes` | Multiline text | evidence of completion |

## Table: Site  (`nm_site`)
| Display name | Logical name | Type |
|---|---|---|
| Site name | `nm_name` | Text (primary) |
| Building / area | `nm_area` | Text |
| Region | `nm_region` | Text |

## Relationships
- `nm_nearmissreport` **1 : N** `nm_correctiveaction`  (parental or referential; cascade per your policy)
- `nm_site` **1 : N** `nm_nearmissreport`

## Calculated column — Risk score
`nm_riskscore = Value(nm_severity) * Value(nm_likelihood)`  (define as a Dataverse calculated column so it
stays consistent in the app and in Power BI).
