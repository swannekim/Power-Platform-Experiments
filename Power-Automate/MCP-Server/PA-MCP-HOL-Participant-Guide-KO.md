# AI로 Power Automate Flow 만들기 — 참가자 실습 가이드

### L300–400 · GitHub Copilot CLI + FlowAgent MCP Server · KT 실습

> **여러분은 이미 클릭하는 법을 알고 있습니다. 오늘은 '설명하는 법'과 'agent가 만든 것을 디버깅하는 법'을 배웁니다.**

**소요 시간:** 3시간 15분 · **오늘 만들 것:** 실무 수준의 cloud flow 3개
**환경:** 공유 Power Platform environment — **여러분이 만드는 모든 것에 본인 이름을 붙입니다**

> 📄 이 문서는 `PA-MCP-HOL-Participant-Guide.md`(영문)의 한국어판입니다. 구조와 번호는 동일합니다.

---

## 목차

| Part | 시간 | 내용 |
|---|---|---|
| [0. 시작 전에](#part-0--시작-전에) | — | 들어오면서 읽어주세요 |
| [1. Setup](#part-1--setup-020) | 0:00–0:20 | HOL 서버 → Copilot CLI → plugin → 첫 tool 호출 |
| [2. 워밍업](#part-2--워밍업-도구와-친해지기-020035) | 0:20–0:35 | skill 살펴보기. 인증 확인. 첫 성공. |
| [3. Scenario 1 — SLA Triage](#part-3--scenario-1--sla-aware-request-triage-035130) | 0:35–1:30 | 분기, adaptive card, SLA 타이머, 오류 처리 |
| [4. 휴식](#part-4--휴식-130140) | 1:30–1:40 | flow는 켜둔 채로 |
| [5. Scenario 2 — Flow Health Guardian](#part-5--scenario-2--flow-health-guardian-140240) | 1:40–2:40 | 자동화를 감시하는 자동화 |
| [6. Scenario 3 — Access Provisioner](#part-6--scenario-3--self-service-access-provisioner-240305) | 2:40–3:05 | 승인 + Entra + 자동 회수 |
| [7. 패키징](#part-7--만든-것을-패키징하기-305312) | 3:05–3:12 | Solution export = flow-as-code |
| [8. 정리](#part-8--정리-312315) | 3:12–3:15 | agent를 쓰지 *말아야* 할 때 |
| [부록 A — 문제 해결](#부록-a--문제-해결-레퍼런스) | — | 실제로 겪은 모든 에러와 해결책 |
| [부록 B — Skill 레퍼런스](#부록-b--skill-레퍼런스) | — | 각 skill의 용도 |
| [부록 C — 내 환경 카드](#부록-c--내-환경-카드) | — | Setup 중에 채워 넣으세요 |

---

# Part 0 — 시작 전에

## 0.1 오늘 실제로 배우는 것

오늘의 목표는 **"AI가 flow를 만들 수 있다"를 확인하는 것이 아닙니다.** 다음 루프를 익히는 것입니다.

```
describe  →  agent가 실제 ID를 resolve  →  validate  →  create  →  run  →  실패 로그 읽기  →  수정
```

터미널을 벗어나지 않고, 모든 flow 정의를 Git으로 버전 관리할 수 있는 형태로 말이죠.

세 가지 flow는 **디자이너에서 만들기 번거로운 요소**를 하나씩 담고 있습니다. 계산된 마감 시각,
`Configure run after`, 사람의 응답을 기다리는 adaptive card, 병렬 분기, Entra 호출 등입니다.
클릭으로 40분 걸리던 작업이 문장 하나로 줄어듭니다.

**하지만 더 중요한 것은 솔직한 부분입니다.** 바로 이 flow들을 만드는 과정에서 agent는 실제로
이런 일을 했습니다.

- 존재하지 않는 connector operation을 지어냈습니다 (두 번)
- 누가 봐도 맞아 보이는 값을 넘겼는데 런타임에 거부당했습니다
- 약한 모델에서는 Power Automate 요청에 대해 **Azure Logic Apps**를 50분 동안 만들었습니다

오늘 이 세 가지를 모두 보게 됩니다. 그게 핵심입니다. *agent는 여러분이 요청한 대로 만듭니다.
실수까지 포함해서요.*

## 0.2 이름 접미사 — 무엇이든 입력하기 전에 먼저 읽어주세요

우리는 **하나의 공유 environment**를 함께 씁니다. 여러분이 만드는 모든 flow 이름 끝에는 반드시
본인 이름이 들어가야 합니다.

```
HOL S1 — IT Request Triage — sage
```

그리고 테스트용으로 만드는 모든 SharePoint 항목의 Title은 **대괄호 안의 본인 이름으로 시작**해야
합니다.

```
[sage] Production database unreachable
```

이것을 지키지 않으면 20명이 하나의 Teams 채널을 보면서 누구 메시지인지 구분하지 못하게 되고,
누군가는 다른 사람의 flow를 지우게 됩니다.

> **지금 접미사를 정하고 [부록 C](#부록-c--내-환경-카드)에 적어두세요.** 소문자, 공백 없이.
> 오늘 약 15개의 prompt에 등장합니다.

## 0.3 미리 준비해 둔 것

오늘 SharePoint 리스트는 **직접 만들지 않습니다.** 20분이 소모되고 MCP server에 대해 배우는 것도
없기 때문입니다. 아래 리스트는 Contoso 사이트에 이미 준비되어 있습니다.

| List | 사용처 | 내용 |
|---|---|---|
| `IT-Requests` | Scenario 1 | 히스토리 3건. 테스트 행은 여러분이 추가 |
| `Routing-Table` | Scenario 1 | 3행 — **`Incident` 행은 의도적으로 없음** |
| `Flow-Health-Log` | Scenario 2 | 의도적으로 비어 있음 |
| `Privileged-Groups` | Scenario 3 | 실제 Entra group ID가 들어간 4행 |
| `Access-Requests` | Scenario 3 | 히스토리 1건. 테스트 행은 여러분이 추가 |

이 외에도 `IT-Ops` Teams 채널, `HOL-` 접두사가 붙은 임시 Entra group 4개, 그리고 Scenario 2가
찾아낼 **의도적으로 고장 낸 canary flow 3개**가 준비되어 있습니다.

---

# Part 1 — Setup (0:20)

> ⏱️ **이 파트는 선택 사항이 아니며, 나중에 다시 하기 어렵습니다.** 1.4와 1.6을 건너뛰면 참가자
> 절반이 똑같은 방식으로 막힙니다.

## 1.1 작업 환경 열기

1. 책상 카드의 자격 증명으로 **HOL 서버**에 로그인합니다.
2. **VS Code**를 엽니다. `File → Open Folder…` → 바탕화면의 `MCP-Server` 폴더.

다음이 보여야 합니다.

```
MCP-Server/
├── README.md
├── PA-MCP-HOL-Participant-Guide.md       ← 영어 참가자 가이드
├── PA-MCP-HOL-Participant-Guide-KO.md    ← 한국어 참가자 가이드
├── lab-resources/
│   ├── Demo data pack Excel file (.xlsx) ← seed 데이터 + 환경 참조값
│   └── Power-Automate-MCP-Server-Build-Guide-sanitized.md
└── sample-pa-flows/
    ├── KTHandsOn_1_0_0_0.zip             ← 참조용 solution (flow 3개 전부)
    ├── HOLS1ITRequestTriage_1_0_0_0.zip  ← 참조용 solution, S1만
    ├── HOLS2FlowHealthGuardian_1_0_0_0.zip ← 참조용 solution, S2만
    └── HOLS3AccessRequestProvision_1_0_0_0.zip ← 참조용 solution, S3만
```

3. `lab-resources/`의 **demo data pack Excel 파일**을 열고
   **`Environment-Reference`** 시트로 이동합니다. 그 값들을 지금
   [부록 C](#부록-c--내-환경-카드)에 옮겨 적으세요. 오늘 계속 사용합니다.

> `sample-pa-flows/`의 `.zip` 파일은 **정답지**입니다. flow가 도저히 복구 안 되는 상태가 되면
> 해당 solution을 import하고 진행하세요. 다만 직접 만들어보기 전에는 열지 않는 것을 권합니다.

## 1.2 사전 요구사항 확인

VS Code에서 **PowerShell 터미널**을 열고(`` Ctrl+` ``) 실행합니다.

```powershell
node --version      # v18 이상이어야 합니다
az --version        # Azure CLI가 설치되어 있어야 합니다
```

둘 다 나오면 다음으로. 아니라면 손을 들어주세요. 직접 설치하지 마세요.

## 1.3 Azure 로그인 상태 확인 — **`az login`은 실행하지 마세요**

```powershell
az account show
```

계정 정보가 나오면 **끝입니다. 다시 로그인하지 마세요.**

> ### ⛔ 30분을 잃는 가장 흔한 방법
> AI agent가 `az login`을 실행하도록 두지 마세요. `az login --use-device-code`는 코드를 출력한
> 뒤 브라우저 입력을 기다리며 **멈춥니다.** agent는 그 입력을 제공할 수 없습니다. 무한정 멈춰
> 있는 동안 agent는 계속 "working"이라고 말합니다.
>
> 실제 빌드 기록에서 이 실수 하나로 1분 41초의 hang과 그 뒤 1시간의 혼란이 발생했습니다.
> **실제 로그인이 필요하면 여러분이 직접 터미널에서 실행하세요.**

## 1.4 Tenant와 environment 고정하기

FlowAgent는 Azure CLI와 **별도의 인증 캐시**를 사용합니다. 이 단계를 건너뛰면 조용히 다른 tenant를
조회하고, environment가 존재하지 않는다고 말할 수 있습니다.

```powershell
$env:PA_TENANT_ID           = "<tenant-guid-from-your-card>"
$env:PA_DEFAULT_ENVIRONMENT = "<environment-guid-from-your-card>"
```

**`PA_DEFAULT_ENVIRONMENT`가 중요한 이유:** `set_current_env`는 MCP server 프로세스 하나의 수명
동안만 유지됩니다. 이 변수를 설정해 두면 "No environment specified" 계열 에러가 통째로 사라집니다.

## 1.5 Copilot CLI 실행 — 그리고 **모델 고정**

```powershell
copilot
```

그리고 **다른 것을 입력하기 전에 먼저**:

```
/model
```

**Claude Sonnet/Opus** 또는 **GPT-5.3-Codex**를 선택하세요. **절대 Auto로 두지 마세요.**

> ### ⛔ 이것이 각주가 아니라 0번째 단계인 이유
> 실제 실패 기록에서 Auto 모드는 `gpt-5-mini`를 선택했습니다. FlowAgent server는 정상적으로
> 로드되어 **56개 tool이 모두 사용 가능**했지만, 모델은 그 중 **단 하나도 호출하지 않았습니다.**
> 대신 자기가 아는 방식인 ARM template으로 되돌아갔습니다. 그 결과 만들어진 것은 **Azure Logic
> Apps**였습니다. 이는 다른 제품이고, Azure에 존재하며, `make.powerautomate.com`에는 절대
> 나타나지 않습니다.
>
> 그 뒤 50분 동안 진행 중인 척 서술만 했습니다. *"Proceeding now…"*, *"obtaining an access
> token…"*, *"I'll notify you when the consent URL is ready…"* — 그러면서 tool 호출은 전혀 하지
> 않았습니다.
>
> plugin이 완벽하게 설치되어 있어도 약한 모델은 아무것도 만들지 못합니다. 더 나쁘게는,
> 그럴듯해 보이지만 쓸모없는 것을 만듭니다.

## 1.6 Plugin 설치

**Copilot CLI 세션 안에서** 다음을 입력합니다.

```
/plugin marketplace add microsoft/power-platform-skills
```

```
/plugin install power-automate@power-platform-skills
```

그 다음 **CLI를 재시작**합니다(종료 후 `copilot` 다시 실행). MCP server를 로드하기 위해서입니다.

**정상 결과:** 재시작 후 FlowAgent MCP server가 시작되고 **56개 tool**이 노출됩니다.

<details>
<summary><b><code>Marketplace "power-platform-skills" already registered</code> 가 나오면</b></summary>

무시해도 됩니다. 이미 등록된 상태입니다. `add`는 건너뛰고 `install` 줄만 실행하세요.
</details>

<details>
<summary><b><code>Failed to install plugin: Access is denied. (os error 5)</code> 가 나오면</b></summary>

이것은 **권한 문제가 아니라 파일 잠금(file lock)입니다.** 관리자 권한으로 실행해도 해결되지
않습니다. 이전에 실행된 Copilot CLI 세션(VS Code 사이드바에 내장된 것 포함)이
`~/.copilot/installed-plugins/`에 대한 핸들을 잡고 있습니다.

**모든 Copilot CLI와 VS Code 창을 닫고** 다시 시도하세요. 그래도 안 되면 손을 들어주세요.
</details>

## 1.7 `setup` skill 실행

```
/setup
```

Node, Azure CLI, 로그인 상태, 토큰 접근 권한, FlowAgent tool 연결 여부를 순서대로 점검하고,
마지막에 여러분의 environment 목록을 보여줍니다.

**이것이 오늘 첫 번째 skill입니다.** 이 skill이 **하지 않은 일**에 주목하세요. 무언가를 설정하라고
요구하지 않았습니다. 점검하고, 보고하고, 고칠 수 있는 것은 고쳤습니다.

## 1.8 가드레일 prompt 붙여넣기

오늘 입력하는 것 중 가장 가치 있는 내용입니다. **모든 실습 세션의 첫 메시지로 붙여넣으세요.**

```
Use the flowagent MCP tools only. Do not use az, ARM templates, or Logic Apps.
Do not run az login — I am already authenticated.
Always resolve display names to GUIDs with resolve_entity / list_tables / search_operations.
Never guess an operation ID or an enum value — look it up and tell me if it does not exist.
Sequence: set_current_env → pick_or_create_connection → resolve_entity →
validate_flow → preflight_flow → create_flow → publish_flow.
When adding to a flow that already exists, use edit_flow or update_flow — do not delete
and recreate it, and do not re-send connectionRefs on an update.
SharePoint update actions require item/Title even when only changing Status.
After each tool call, tell me which tool you called and what it returned.
If you cannot complete a step with an MCP tool, stop and ask me — do not improvise a workaround.
```

이 중 다섯 문장이 실질적인 역할을 합니다.

| 문장 | 막아주는 것 |
|---|---|
| *"flowagent MCP tools only… no ARM or Logic Apps"* | 50분짜리 Logic Apps 삽질 |
| *"never guess… tell me if it does not exist"* | 지어낸 operation ID. 저장 시점 또는 더 나쁘게는 런타임에 실패 |
| *"use edit_flow or update_flow — do not delete and recreate"* | Prompt 3·4·5 사이에서 flow ID가 바뀌어 버리는 상황 |
| *"do not re-send connectionRefs on an update"* | `connection reference … could not be found` — update가 실패하는 유일한 실제 원인 |
| *"SharePoint update actions require item/Title"* | `validate_flow`가 **잡아내지 못하는** publish 시점 거부 |
| *"tell me which tool you called"* | 조용한 stall — 실제로 작업이 진행 중인지 **눈으로** 확인 가능 |

> ### 이 중 두 문장이 들어간 이유
> 각 scenario의 prompt 사다리는 **점진적**입니다. Prompt 2가 flow를 만들고 Prompt 3–5가 거기에
> 덧붙입니다. 이 flow들에 대해 `edit_flow`(부분 수정)와 `update_flow`(전체 정의 교체)는 둘 다
> 정상 동작합니다 — **실제로 검증했습니다.** 다만 update 시 `connectionRefs`를 다시 보내면
> 실패합니다. `create_flow`가 flow를 solution에 넣으면서 connection이 논리 이름이 다른
> *connection reference*로 바뀌기 때문입니다. 다시 보내지 말라고 지시하면 이 실패 요인이
> 사라집니다.
>
> 그리고 `item/Title`은 상태만 바꾸는 경우에도 **모든** SharePoint 업데이트에 필요합니다. 이
> 에러는 `validate_flow`와 `preflight_flow`가 모두 통과한 뒤 **publish 시점**에 나타납니다.

## 1.9 Stall 신호 알아두기

agent가 **"Proceeding now…"** 라고 말하는데 **tool 호출이 보이지 않으면** **Esc**를 누르세요.

서술은 작업이 아닙니다. tool 호출이 0이라는 것은 plugin이 사용되지 않고 있다는 뜻입니다. 일찍
중단하고 다시 지시하세요. *"Use the flowagent MCP tools."*

---

# Part 2 — 워밍업: 도구와 친해지기 (0:20–0:35)

목표는 두 가지입니다. 모두가 성공 결과를 한 번 보는 것, 그리고 이후 모든 작업의 기반이 되는
습관을 익히는 것.

## 2.1 Plugin이 연결됐는지 확인

```
List my Power Automate environments.
```

**정상 결과:** 공유 실습 environment를 포함한 실제 environment 이름들.

그 외의 것이 나온다면 — 사과문이든, 일반적인 설명이든, "도와드리겠습니다" 같은 제안이든 —
**plugin이 사용되지 않고 있거나 모델이 약한 것입니다.** 1.5로 돌아가세요. 그냥 진행하지 마세요.

## 2.2 `browse-flows` skill 사용해보기

```
/browse-flows
```

environment와 그 안의 flow들을 둘러보세요. 해당 환경을 사용하는 다른 user들의 flow를 확인할 수 있습니다.

## 2.3 대부분의 실패를 막아주는 습관: **만들기 전에 resolve하기**

```
Set my environment to <env-name>. Then:
1. list the SharePoint lists on https://<tenant>.sharepoint.com/sites/Contoso
   and show me the columns of IT-Requests and Routing-Table
2. resolve the Teams team "Contoso" and the channel "IT-Ops" to GUIDs
3. show me which connections already exist and their status
Do not create anything yet — just report what you resolved.
```

반환된 GUID를 전부 [부록 C](#부록-c--내-환경-카드)에 옮겨 적으세요.

### 이것이 단순 작업이 아닌 이유

Connector operation은 **표시 이름(display name)을 받지 않습니다.**
`/v1/teams/Contoso/channels/IT-Ops/messages` 같은 경로는 합리적으로 보이지만 **항상 틀립니다.**
실제 connector는 `19:689fec82…@thread.tacv2` 같은 GUID를 요구합니다.

`resolve_entity`가 반환하는 `confidence` 필드를 확인하세요. **`exact`**여야 합니다. `ambiguous`가
나오면 후보 목록을 함께 보여주는데, 이때는 **만들기 전에 반드시 확인**해야 합니다. 그렇지 않으면
엉뚱한 Teams 채널에 프로비저닝하게 됩니다.

## 2.4 agent가 직접 찾아보게 하기

```
What operations does the SharePoint connector expose for a "when an item is created"
trigger? Give me the exact operation ID. Do not guess.
```

**정상 결과:** `GetOnNewItems`.

직관적으로 떠올리는 이름은 `OnNewItems`입니다. 그런 것은 존재하지 않습니다. 실제 빌드에서는
추측한 식별자 4개가 **4개 모두** 틀렸습니다.

| 추측 | 실제 | 확인에 사용한 tool |
|---|---|---|
| `OnNewItems` | **`GetOnNewItems`** | `search_operations` |
| `PostCardToConversationAndWaitForResponse` | ❌ 아예 존재하지 않음 | `get_operation_details` |
| `CustomResponses` | **`CustomResponse`** (단수형) | `invoke_operation` → `GetApprovalTypes` |
| `ApprovalCreationInput/…` | **`WebhookApprovalCreationInput/…`** | `resolve_params` |

틀린 추측 하나마다 create → publish → 실패 사이클을 온전히 한 번 소모합니다. 읽기 전용 조회는
몇 초면 끝납니다.

✅ **체크포인트:** environment 목록 확인, team과 channel이 `exact`로 resolve됨, 그리고
`GetOnNewItems`가 왜 `OnNewItems`가 아닌지 이해함.

---

# Part 3 — Scenario 1 — SLA-Aware Request Triage (0:35–1:30)

## 3.1 비즈니스 상황

모든 IT 팀에는 접수 리스트가 있습니다. 진짜 일은 티켓 자체가 아니라 **뒤치다꺼리**입니다.
담당자 배정, 담당자 독촉, SLA 임박 감지, 관리자 에스컬레이션. 이 flow는 그 네 가지를 모두
수행하며, 절대 잊어버리지 않습니다.

## 3.2 배우게 될 것

**Flow 측면:**
- 데이터 기반 라우팅 — 담당자와 SLA를 하드코딩이 아니라 lookup table에서 가져옵니다
- 직접 작성하면 오타 나기 쉬운 계산식으로 마감 시각 산출
- **사람의 응답을 기다리는** adaptive card, 그리고 사용자 정의 응답이 있는 approval
- 실행 중인 인스턴스 안의 실제 SLA 타이머, 그리고 그것이 왜 **병렬로** 동작해야 하는지
- `Scope` + `Configure run after` — 실무 flow의 80%가 빠뜨리는 부분

**Agent로 만드는 측면:**
- 매 create 전에 `validate_flow`와 `preflight_flow`를 돌리면 사이클이 절약되는 이유
- 플랫폼의 에러 메시지는 정확하며, agent가 그것을 보고 수정할 수 있다는 점
- agent는 생성기일 뿐 아니라 **디버거**라는 점

## 3.3 목표 아키텍처

```
TRIGGER  SharePoint · When an item is created (IT-Requests, polls 1 min)
│
└─ SCOPE "Triage"
   ├─ Get the routing row for this RequestType
   ├─ Compute the SLA minutes from Priority, and DueBy = now + SLA
   ├─ Update the item: AssignedTo, Status = Assigned, DueBy
   │
   ├── BRANCH A — Switch on Priority
   │     ├─ P1 → adaptive card to IT-Ops + approval (Acknowledge / Reassign)
   │     ├─ P2 → Teams chat to the owner
   │     └─ P3 → email to the owner
   │
   └── BRANCH B — wait until 1 minute before DueBy      ← BRANCH A와 병렬 실행
         → re-read the item
         → if Status is still not In Progress / Closed → Escalate + post to IT-Ops

SCOPE "Handle failure"  runs only if Triage failed or timed out
   → report the failing action + error to IT-Ops → terminate as Failed
```

> ### ⚠️ Branch B가 병렬이어야 하는 이유 — 이해할 가치가 있는 설계 버그
> 직관적인 설계는 SLA 대기를 Switch **뒤에** 둡니다. 그런데 P1 분기는 사람의 응답을 기다립니다.
> 순차 구조라면 아무도 클릭하지 않을 때 flow가 **에스컬레이션 단계에 영원히 도달하지 못합니다.**
> 즉 SLA가 가장 필요한 우선순위인 P1만 유일하게 에스컬레이션되지 않습니다.
>
> 이 문제는 원래 실습 설계안에 그대로 있었고, 실제로 만들어보고 나서야 발견됐습니다. 아래
> prompt처럼 병렬 버전을 요청하세요.

## 3.4 Prompt 사다리

### Prompt 1 — agent에게 기준 잡아주기

```
Set my environment to <env-name>. Show me the columns of the SharePoint lists
IT-Requests and Routing-Table, and resolve the Teams team "Contoso" and channel
"IT-Ops" to GUIDs. Report what you resolved. Do not create anything yet.
```

### Prompt 2 — 뼈대 만들기

```
Create a flow named "HOL S1 — IT Request Triage — <yourname>" in this environment.

Trigger: when an item is created in the SharePoint list IT-Requests.
Then: get items from Routing-Table filtered to Title equal to the new item's
RequestType, and take the first match.
Update the new item with AssignedTo = the routing row's OwnerEmail,
Status = "Assigned", and DueBy = utcNow() plus the SLA minutes for the item's
Priority (SLAMinutes_P1 / _P2 / _P3 on the matched routing row).

Choice columns come through as objects — read them as RequestType/Value and
Priority/Value. Use addMinutes with an integer.
Validate and preflight before creating. Do not publish yet.
```

> **마지막 문단이 들어간 이유.** `addMinutes`/`addHours`/`addDays`는 **정수** 인자를 요구합니다.
> 소수 값을 넣으면 저장은 깔끔하게 되고 **런타임에 터집니다.** 가장 비싼 종류의 버그입니다.
> 그리고 `Priority/Value` 대신 `Priority`를 읽으면 Switch가 조용히 default로 빠져서 모든 요청이
> P3 이메일을 받게 되는데, *겉보기에는 아무 문제가 없어 보입니다.*

### Prompt 3 — 알림 분기

```
Add a Switch on the trigger item's Priority/Value.

P1: post an adaptive card to the Teams channel IT-Ops showing the request title,
type, requester and DueBy. Then start an approval with custom responses
"Acknowledge" and "Reassign", assigned to <your-own-email>. When it comes back
Acknowledge, set the item Status to "In Progress".

P2: send a Teams chat from the Flow bot to the assigned owner.
P3 (default): send an email to the assigned owner.

Re-validate and preflight.
```

> **참고:** approval을 **본인 이메일**로 배정해서 각자 자기 데모를 진행할 수 있게 합니다.
> *배정(assignment)* 자체는 여전히 routing table에서 오며, 그것이 데이터 기반 설계 부분입니다.

### Prompt 4 — SLA 타이머 (아무도 손으로 안 만드는 부분)

```
Add a second branch that runs in PARALLEL with the Switch, starting from the
update action — not after the Switch.

It should wait until one minute before DueBy, then re-read the item. If the item's
Status/Value is not "In Progress" and not "Closed", set Status to "Escalated",
increment EscalationCount, and post a message to IT-Ops naming the routing row's
EscalationEmail and the request title.
```

### Prompt 5 — 운영 수준으로 다듬기

```
Wrap everything in a scope called "Triage". Add a second scope "Handle failure"
configured to run only when Triage has failed or timed out. It should filter
result('Triage') for failed actions, post the failing action name and error message
to IT-Ops, then terminate the flow as Failed.

Validate, preflight, create, and publish. Then confirm with list_flows that the
state is actually Started.
```

> **`result('Triage')`** 는 *"flow가 어딘가에서 실패했다"* 를 *"action X가 메시지 Y로 실패했다"* 로
> 바꿔주는 관용구입니다. 이 flow에서 가장 유용한 부분이며, 문장 하나로 요청할 수 있습니다.
>
> **그리고 마지막 줄에 주목하세요.** `publish_flow`는 실제 활성화가 실패했는데도
> `{"success": true}`를 반환할 수 있습니다. 진짜 에러는 서버 로그에만 나타납니다.
> **반드시 `list_flows`로 확인하세요.**

### Prompt 6 — 동작 확인

```
Add an item to IT-Requests with Title "[<yourname>] New laptop for contractor
onboarding", RequestType Hardware, Priority P2, Requester <a demo account>.
Then show me the run history for my flow and explain what each action returned.
```

> ### ⏱️ 기다려야 정상입니다. 버그가 아닙니다
> 새로 활성화된 SharePoint trigger는 **첫 실행까지 최대 1시간**이 걸릴 수 있습니다. 실제 빌드
> 측정값: 15:25 활성화, 16:24 첫 실행 — **59분**. 그 이후로는 정상 주기로 폴링합니다.
>
> **정상 동작하는 flow를 "고치려" 들지 마세요.** 실행 기록이 없으면 활성화한 지 얼마나 됐는지부터
> 확인하세요. 휴식 전에 flow를 활성화하는 이유가 이것입니다.

**정상적인 실행은 이렇게 보입니다.**

| Action | 상태 | 확인되는 것 |
|---|---|---|
| `Compose_routing` | Succeeded | routing lookup이 매칭됨 |
| `Assign_the_request` | Succeeded | 항목이 업데이트됨 |
| `Chat_the_owner` | Succeeded | P2 분기가 실행됨 |
| `Email_the_owner` | **Skipped** | ✅ Switch가 `P2`에 매칭됨 — default로 빠지지 **않음** |

여기서 중요한 것은 **Skipped** 행입니다. *아무 일도 하지 않아야 할* 분기를 확인하는 것이야말로
라우팅이 제대로 동작한다는 증거입니다. 초록색 체크 표시가 아니라요.

## 3.5 의도된 실패 — 오늘 가장 값진 10분

`Routing-Table`에는 **`Incident` 행이 없습니다.** 의도적으로요.

```
Add an item to IT-Requests with Title "[<yourname>] Mail relay dropping outbound
messages", RequestType Incident, Priority P1.
```

routing lookup이 빈 배열을 반환하고, `value[0]`에서 실패하며, 여러분이 만든 failure scope가
IT-Ops에 보고합니다. 이제 **agent와 함께** 디버깅합니다.

```
/debug-flow
```

또는 자율 진단 버전:

```
My flow just failed. Get the run history, find the failing action, explain the root
cause, and fix the flow so an unmatched RequestType falls back to a DEFAULT routing
row and posts a warning instead of failing.
```

**`/diagnose-flow`** 도 실행해보세요. 대화형으로 안내하는 대신, 실패한 각 action을 분류하고
조치 방안을 제시합니다.

**이 순간 참가자들이 이해하게 됩니다.** agent는 생성기가 아니라 디버거라는 것을요. 실제 실행
기록을 읽고, 실패한 action을 찾고, 정의를 고쳤습니다.

## 3.6 문제 해결 — Scenario 1

| 증상 | 원인 | 해결 |
|---|---|---|
| `validate_flow`가 `extra-authentication` 반환 | **action** 안에 `$authentication`이 있음 | **trigger에만** 들어갑니다. Flow API가 action에 자동 주입합니다 |
| 저장 실패: `missing required property 'item/Title'` | Title 없는 `PatchItem` | 상태만 바꾸는 경우에도 **모든** 업데이트에 `item/Title`을 넣으세요 |
| 모든 요청이 P3 이메일 분기로 감 | `Priority/Value`가 아니라 `Priority`를 읽음 | Choice 컬럼은 객체입니다 |
| 에스컬레이션이 즉시 발생 | 지연 오프셋이 SLA보다 큼 | 분 단위 SLA에서는 minus 1 hour가 아니라 `addMinutes(DueBy, -1)` |
| 저장은 됐는데 상태가 `Stopped` | `publish_flow`의 거짓 성공 | 다시 publish하고 `list_flows`로 확인, 서버 로그 읽기 |
| 실행이 전혀 없음 | 첫 폴링 지연 | 최대 1시간 대기. trigger가 `GetOnNewItems`인지 확인 |
| 실행 기록이 갱신되지 않음 | 새로 **생성된** 항목이 없음 | trigger는 **생성 시에만** 동작합니다. 행 수정은 아무 효과 없음 |

---

# Part 4 — 휴식 (1:30–1:40)

**flow는 Started 상태로 두세요.** 첫 폴링 지연 때문에, 돌아왔을 때 flow가 준비된 상태가 됩니다.

---

# Part 5 — Scenario 2 — Flow Health Guardian (1:40–2:40)

> *"운영 중인 flow가 60개입니다. 누가 감시하고 있나요? 아무도 없습니다. 15분 안에 해결해봅시다."*

## 5.1 비즈니스 상황

Power Automate의 기본 실패 알림은 소유자별·flow별로 오고, 무시하기 쉬우며, 테넌트 전체를 보는
관점을 주지 못합니다. 조용한 실패는 며칠 뒤 화난 현업 사용자가 발견하게 됩니다.

이 flow는 **자동화 자산에 대한 자동 운영 스탠드업**입니다. 실패한 실행을 수집하고, 분류하고,
기록하고, 운영 채널에 요약 카드 하나를 게시합니다.

## 5.2 배우게 될 것

**Flow 측면:** Dataverse `flowruns` 테이블, 배열 필터링, 중첩 표현식을 이용한 분류,
동시성 제어가 있는 `Apply to each`, 그리고 "아무 문제 없음" 분기.

**Agent로 만드는 측면 — 그리고 이것이 진짜 교훈입니다:** connector가 **필요한 기능을 제공하지
않을 때** 무엇을 해야 하는가.

## 5.3 먼저 막다른 길을 발견하기 (건너뛰지 마세요)

```
Show me every operation the Power Automate Management connector exposes for listing
flows, listing flow runs, and resubmitting a run. Give me exact operation IDs.

Is there any operation that can LIST flow runs? If not, say so explicitly — do not
substitute a similar-sounding one. Don't build anything yet.
```

**예상 답변: flow run을 나열하는 operation은 존재하지 않습니다.** 빌드 과정에서 24개 operation을
전부 확인했습니다. `ResubmitFlow`와 `CancelFlowRun`은 둘 다 **이미 알고 있는** `runId`를
요구합니다. 즉 이 connector는 실행을 *조치*할 수는 있지만 *발견*할 수는 없습니다.

원래 실습 설계는 존재하지 않는 그 operation 위에 세워져 있었습니다. 읽기 전용 prompt 하나로
알아냈습니다.

> ### 💡 이 실습에서 가장 널리 쓸 수 있는 개념
> agent는 operation을 지어내지 않고 부재를 보고했습니다. 정확히 우리가 원하는 동작입니다.
> 두려워해야 할 실패 방식은, 모델이 태연하게 `ListFlowRuns`를 정의에 써넣고, 저장하고,
> 런타임에 죽는 물건을 건네주는 것입니다.
>
> **하지만 "이 connector가 못 한다"와 "이건 불가능하다"는 다릅니다.** 이어서 질문하세요.

```
Flow runs must be recorded somewhere. Is there a Dataverse table that holds flow run
history? Show me its columns.
```

**답: `flowruns` 테이블입니다.** `status`, `errorcode`, `errormessage`, `starttime`,
`_workflow_value`를 담고 있고 28일간 보관되며, **Standard 등급 Dataverse connector**로 조회할 수
있습니다.

이 방식이 원래 설계보다 *더 낫습니다.* *list flows → 각 flow마다 → 실행 목록 조회* 라는 N+1 패턴
대신, 서버에서 필터링되는 단일 조회 한 번이면 됩니다. N+1 패턴은 flow가 500개가 되면 무너집니다.

## 5.4 Prompt 사다리

### Prompt 1 — 뼈대

```
Create a flow "HOL S2 — Flow Health Guardian — <yourname>" in this environment.

Trigger: recurrence every 15 minutes.
Use the Dataverse connector to list rows from the flowruns table, filtered to
status eq 'Failed' and starttime greater than 24 hours ago. Select name, status,
errorcode, errormessage, starttime, _workflow_value and resourceid. Order by
starttime descending, top 50.

Validate and preflight. Do not publish yet.
```

### Prompt 2 — 자기 자신을 먹지 않게 하기

```
Add a filter that excludes this flow's own runs, comparing each row's resourceid to
workflow()?['name']. Also filter to only the flows whose name ends with "<yourname>"
so I only see my own failures in this shared environment.
```

> **여기서 두 필터는 선택이 아니라 필수입니다.** 15분 주기에서 Guardian은 자기 자신을 목록에
> 포함하고, 자기 자신을 기록하며, resubmit 단계까지 붙이면 자기 자신을 재실행하게 됩니다.
> 그리고 공유 environment에서 이름 필터가 없으면 20명분의 실패를 전부 보게 됩니다.

### Prompt 3 — 분류와 기록

```
For each failed run, compute a classification:
- Transient if the error code is 429, 500, 502, 503 or 504, or the message contains
  "timeout" or "throttl"
- Structural if the code is 400, 401, 403 or 404, or the message contains
  "connection" or "expired"
- otherwise Unknown

Create an item in the SharePoint list Flow-Health-Log with the flow id, run id,
error code, error message, run start time and classification. Set Status to
"Resubmitted" for Transient, "Escalated" for Structural, "Failed" for Unknown.
Set the loop concurrency to 1.
```

### Prompt 4 — 재시도 폭주 방지

```
Before logging a run, check Flow-Health-Log for an item with the same RunId. If one
already exists, skip that run entirely.
```

> ### ⚠️ 이것은 부가 기능이 아니라 정확성 수정입니다 — 실제로 확인됨
> 참조 빌드에서 Guardian을 약 6시간 방치했습니다. `Flow-Health-Log`에는 **단 하나의 실패 실행에
> 대해 25개 행**이 쌓였습니다. 24시간 범위를 계속 조회하면서, 이미 무엇을 기록했는지에 대한
> 기억이 없기 때문에 매 주기마다 같은 실패를 다시 기록한 것입니다.
>
> ```
> total rows: 25   distinct RunIds: 1
>   08584152156028960900548418611CU10  logged 25x
> ```
>
> 여기에 resubmit 단계까지 연결되어 있었다면 **실패하는 실행을 25번 재실행**했을 것입니다.
> *agent는 요청하면 기꺼이 지뢰를 만들어 줍니다.*

### Prompt 5 — 요약 카드

```
After the loop, post one adaptive card to the Teams channel IT-Ops with the total
failed runs, how many were resubmitted, how many escalated, and the number of
distinct flows affected. If there were zero failures, post a short "all healthy"
message instead.

Wrap it all in a scope with a failure handler that reports to IT-Ops.
Validate, preflight, create and publish, then confirm the state with list_flows.
```

### Prompt 6 — 동작 확인

```
Trigger this flow now and show me the run history. Then show me the items it created
in Flow-Health-Log.
```

수명 주기 작업에는 **`manage-flows`** skill도 사용할 수 있습니다.

```
/manage-flows
```

## 5.5 하이라이트

강사가 오늘 아침에 고장 낸 canary flow들을 대상으로 실행해보세요. 고장 난 flow 3개가 발견되고,
분류되고, 기록되고, Teams 카드가 게시되는 것을 봅니다. 영어 문장 다섯 개로 만든 결과입니다.

그리고 이 한마디:

> *"이 flow는 environment의 모든 flow를 감시합니다. 자기 자신까지 포함해서요. 그래서 자기 자신은
> 빼도록 가르쳐야 했던 겁니다."*

**그리고 빌드 중 실제로 있었던 일:** Scenario 3을 아직 만드는 중이었는데 Guardian이 **Scenario 3의
실패를 잡아냈습니다.** canary가 아니라 진짜 버그였고, 다른 실습 flow에서 발생했으며, 다른 flow를
감시하는 것이 존재 이유인 바로 그 flow가 발견했습니다.

## 5.6 문제 해결 — Scenario 2

| 증상 | 원인 | 해결 |
|---|---|---|
| agent가 "List Flow Runs"를 제안 | 추측한 것 | 그런 operation은 없습니다. Dataverse `flowruns`로 유도하세요 |
| 요약이 항상 비어 있음 | 조회 범위에 실패 실행이 없음 | canary가 **최근 24시간 내**에 실패했어야 합니다. 다시 실행하세요 |
| Guardian이 자기 자신을 기록 | 자기 제외 필터 없음 | `resourceid`와 `workflow()?['name']` 비교 |
| 다른 사람 실패가 보임 | 이름 필터 없음 | 이름 접미사로 끝나는 flow만 필터링 |
| 같은 실행이 반복 기록됨 | 중복 제거 없음 | Prompt 4의 `RunId` 조회를 추가 |
| `flowruns` 조회 결과가 없음 | `starttime` 필터 문법 오류 | agent에게 `get_expression_help`로 날짜 필터를 확인하도록 요청 |

---

# Part 6 — Scenario 3 — Self-Service Access Provisioner (2:40–3:05)

> *"스스로 프로비저닝되는 접근 요청 — 승인자, 감사 추적, 그리고 회수 날짜까지 포함해서."*

## 6.1 비즈니스 상황

*"Marketing 그룹에 저 좀 추가해 주세요."* 현재는 티켓, 담당자, 복사-붙여넣기, 그리고 **만료 없음**
입니다. 2주짜리 프로젝트를 위해 부여한 권한이 2년 뒤에도 그대로 남아 있습니다. 이 flow는 그
고리를 닫고 **자동으로 회수**합니다.

## 6.2 배우게 될 것

- **2단계 조건부 승인** — 일반 그룹은 관리자, 권한 그룹은 보안 담당자
- flow에서 **Entra에 쓰기** — 실제로 검증 가능한 상태 변경
- **기한이 있는 접근 권한과 자동 회수** — 실질적인 컴플라이언스 이점
- **파라미터의 이름이 곧 규약은 아니라는 점** — 오늘 가장 날카로운 교훈

## 6.3 Prompt 사다리

### Prompt 1 — 도구 존재 확인

```
I need to add and remove Entra group members from a flow. Show me which connector
can do that and its exact operation IDs. Confirm the connection exists and is
Connected — if it is not, stop and tell me.
```

**예상 결과:** **Microsoft Entra ID** connector (`shared_azuread`, **Standard** 등급)의
`AddUserToGroup`과 `RemoveMemberFromGroup`.

> 여기서 **필요하지 않았던 것**에 주목하세요. 프리미엄 *HTTP with Microsoft Entra ID* connector와
> 직접 작성한 Graph URL입니다. 참조 빌드의 첫 시도는 불필요하게 그 길로 갔습니다. connector가
> 이미 무엇을 제공하는지 항상 먼저 확인하세요.

### Prompt 2 — 승인

```
Create a flow "HOL S3 — Access Request Provisioner — <yourname>".

Trigger on item created in Access-Requests. Look up the item's TargetGroup/Value in
Privileged-Groups to get GroupId, IsPrivileged and SecurityOwnerEmail. Get the
requester's manager with Office 365 Users.

Start an approval assigned to the manager. If the outcome is not Approve, set Status
to "Rejected", notify IT-Ops, and terminate.

Validate and preflight. Do not publish.
```

### Prompt 3 — 권한 그룹 경로

```
If the matched group's IsPrivileged is true — it is a real boolean, compare to true,
not to the string "Yes" — add a second approval assigned to SecurityOwnerEmail, with
the same rejection path.

Both rejection paths must terminate BEFORE any Entra call.
```

> **순서는 스타일이 아니라 컴플라이언스 문제입니다.** *"승인은 정상적으로 거부됐는데 프로비저닝은
> 됐다"* 는 감사 지적 사항입니다. 뒤에서 정상 경로 실행 시 두 거부 분기가 모두 **Skipped**로
> 표시되는지 확인하게 됩니다.

### Prompt 4 — 프로비저닝

```
On full approval, resolve the requester's Entra object id with Office 365 Users, then
add them to the group with the Microsoft Entra ID connector.

Check the connector's swagger for what the user-id parameter actually expects before
you build it — do not assume it takes a Graph URL. Connector object parameters use
slash-flattened keys, so it is body/@odata.id, not a nested body object.

Then set Status to "Provisioned", GrantedOn to utcNow(), and
ExpiresOn to utcNow() plus DurationMinutes. Use addMinutes with an integer.
```

> ### 🔍 이 prompt가 막아주는 함정
> `AddUserToGroup`에는 **`@odata.id`** 라는 이름의 파라미터가 있습니다. 원래 Graph API에서 이 키는
> 전체 URL을 받습니다: `https://graph.microsoft.com/v1.0/directoryObjects/{id}`.
>
> **그런데 connector는 GUID만 요구합니다.** URL은 connector가 직접 만듭니다. URL을 넘기면 URL 안에
> URL을 감싸게 되고, Graph는 이렇게 응답합니다.
>
> ```
> Request_BadRequest: Unexpected segment DynamicPathSegment. Expected property/$value.
> ```
>
> 저장도 됐고, 게시도 됐고, `validate_flow`와 `preflight_flow`를 **둘 다 통과**했습니다. 실제
> 실행이 여기에 도달했을 때 비로소 실패했습니다. 유일한 근거는 connector의 swagger였고, 거기에
> `x-ms-summary`는 `"User Id"`, 예시 값은 GUID 하나였습니다.
>
> **preflight 통과는 정의가 올바른 형식이라는 뜻이지, 내용이 맞다는 뜻이 아닙니다.**

### Prompt 5 — 회수

```
After ExpiresOn, remove the member from the group and set Status to "Revoked", then
notify. Wrap everything in a scope with a failure handler that reports to IT-Ops.
Validate, preflight, create, publish, and confirm with list_flows.
```

### Prompt 6 — 전 구간 확인

```
Add an item to Access-Requests: Title "[<yourname>] Falcon access", Requester
<demo account>, TargetGroup "HOL-Project Falcon", DurationMinutes 5, Status Pending.
Then watch the run.
```

승인 요청이 오면 승인하세요. 그리고 **Entra에서 직접** 멤버가 추가됐는지 확인하고, 5분 뒤에
사라졌는지도 확인하세요. flow가 스스로 기록한 상태 필드를 믿지 마세요. 그게 감사 추적의 존재
이유입니다.

## 6.4 솔직한 마무리

> *"`Delay Until`은 해당 기간 내내 flow 인스턴스를 열어둡니다. 5분이면 괜찮습니다. 90일이면
> 아닙니다. 실무에서는 `ExpiresOn`이 지난 항목을 야간 배치로 훑는 방식으로 회수를 옮깁니다.
> agent는 여러분이 요청하는 쪽을 만들어 줍니다. 어느 쪽을 요청해야 하는지 아는 것은 여전히
> 여러분의 몫입니다."*

## 6.5 문제 해결 — Scenario 3

| 증상 | 원인 | 해결 |
|---|---|---|
| `Unexpected segment DynamicPathSegment` | `@odata.id`에 전체 Graph URL을 넘김 | **GUID만** 넘기세요 |
| 저장 실패: `missing required property 'body/@odata.id'` | 본문을 중첩 JSON으로 보냄 | 평탄화된 키 `body/@odata.id` 사용 |
| 승인 요청이 오지 않음 | 요청자에게 manager가 없음 | Entra에서 확인. 승인자가 null이면 조용히 실패합니다 |
| 권한 그룹인데 승인이 1단계만 | `IsPrivileged`를 문자열로 비교 | boolean입니다. `true`와 비교하세요 |
| 거부했는데 멤버가 추가됨 | 거부 분기가 Entra 호출보다 뒤에 있음 | 순서 변경. 프로비저닝 전에 종료 |
| `InvalidApprovalType` | enum을 추측함 | `CustomResponse`, 단수형. `invoke_operation` → `GetApprovalTypes`로 확인 |
| Graph가 그룹에 404 반환 | 자리표시자 값이거나 동적 그룹 | 실제 object ID 사용. 동적 멤버십 그룹은 수동 쓰기를 거부합니다 |

---

# Part 7 — 만든 것을 패키징하기 (3:05–3:12)

여러분의 flow는 포털 안의 산출물이 아니라, 승격 가능한 코드입니다.

```
/manage-flows
```

그리고:

```
Give me an inventory of the flows I own in this environment, with their state and
last modified time.
```

## Solution으로 내보내기

`make.powerautomate.com` → **Solutions** → **New solution** → **Add existing → Cloud flow**로
flow 3개를 추가합니다.

**그리고 connection reference도 반드시 추가하세요** — `Add existing → Connection reference`.

> ### Connection reference는 넣고, connection은 넣지 않는 이유
> flow만 담은 solution은 **connection 바인딩이 전혀 없는 상태로** export됩니다. 빌드 과정에서
> 직접 확인했습니다. import 시 아무것도 매핑할 수 없습니다.
>
> **Connection**은 사용자별·environment별 자격 증명이며, 의도적으로 solution 구성 요소가
> *아닙니다.* **Connection reference**가 이식 가능한 추상화이며, import 시 각 reference를 대상
> environment의 실제 connection에 연결하도록 안내합니다.
>
> SharePoint 리스트, Teams 채널, Entra group 역시 solution 구성 요소가 **아닙니다.** 대상
> environment에서 다시 만들고 GUID를 다시 지정해야 합니다.

**Export → Unmanaged → zip 다운로드.** 폴더에 있는 `KTHandsOn_1_0_0_0.zip`과 비교해보세요.

**솔직한 약점:** SharePoint 리스트 GUID, Teams 채널 ID, Entra group ID가 정의에 하드코딩되어
있습니다. 제대로 승격하려면 이 값들을 **environment variable**로 옮겨야 하며, 그것이 자연스러운
L400 후속 주제입니다.

---

# Part 8 — 정리 (3:12–3:15)

## 실패 분류표 — 모두 실제로 발생한 것들

| 실패 | 신호 | 해결 |
|---|---|---|
| flow 작업인데 agent가 ARM / `az`를 사용 | MCP tool 호출 0건, resource group 이야기 | **중단시키세요.** Logic Apps ≠ Power Automate. 모델을 다시 고정 |
| Auto 모드가 약한 모델 선택 | tool 56개 로드, 호출 0건 | `/model`. 가장 효과가 큰 조치 |
| 몇 분째 "Proceeding now…" | tool 호출 없는 서술 | **Esc.** 가드레일 prompt 다시 제시 |
| operation ID나 enum을 지어냄 | `ApiOperationNotFound`, `InvalidApprovalType` | 조회하세요. 추측 4건 중 4건이 틀렸습니다 |
| 값은 맞아 보이는데 런타임 실패 | preflight 통과, 실행 시 `BadRequest` | connector swagger를 읽으세요 |
| 활성화했는데 실행이 없음 | 빈 실행 기록 | 첫 폴링에 1시간까지 걸립니다. 진단하기 전에 기다리세요 |
| "connector가 못 한다" | operation 부재 | *이 데이터가 다른 어디에 있는가?* 를 물으세요 |

## 기억할 만한 숫자

| Flow | 완성까지 걸린 빌드 사이클 |
|---|---|
| Scenario 1 | **6** |
| Scenario 2 | **0** |
| Scenario 3 | **2** |

Scenario 2는 한 번에 성공했습니다. Scenario 1에서 겪은 모든 실패를 먼저 적용한 뒤에 작성했기
때문입니다. **에러가 곧 커리큘럼입니다.** 여러분의 실무도 같은 순서로 배치하세요.

## 마무리 관점

MCP server는 flow 지식을 대체하지 않습니다. **클릭을 없애줄 뿐입니다.** `Delay Until`이 인스턴스를
열어둔다는 것, `Apply to each`가 스로틀링 한계에 부딪힌다는 것, 재시도에는 상한이 필요하다는 것,
승인이 쓰기보다 앞에 와야 한다는 것 — 이건 여전히 알아야 합니다.

달라진 것은 **시도 비용**입니다. flow를 만들고, 실행하고, 실패를 읽고, 고치는 루프가 40분에서
5분으로 줄었습니다. 그래서 디버깅 역량이 더 가치 있어진 것입니다.

---

# 부록 A — 문제 해결 레퍼런스

## Setup 및 plugin

| 에러 | 의미 | 해결 |
|---|---|---|
| `Marketplace … already registered` | 무해함 | `add` 건너뛰고 `install` 실행 |
| `Access is denied. (os error 5)` | 권한이 아니라 **파일 잠금** | 모든 Copilot CLI / VS Code 창을 닫으세요. 관리자 권한은 **도움이 안 됩니다** |
| `ServiceToServiceEnvironmentNotFound` | FlowAgent 자체 캐시의 tenant가 잘못됨 | `PA_TENANT_ID` 설정 후 `%LOCALAPPDATA%\flowagent\msal-cache`와 `\tokens` 삭제 |
| `No environment specified and no default set` | 프로세스 간 environment 고정이 풀림 | `set_current_env` 재실행 또는 `PA_DEFAULT_ENVIRONMENT` 설정 |
| tool이 나타나지 않음 | plugin 미로드 | 설치 후 CLI 재시작 |

## 저장 시점 에러

| 에러 | 해결 |
|---|---|
| `extra-authentication` | `$authentication`은 **trigger에만** |
| `missing required property 'item/Title'` | 모든 `PatchItem`에 `item/Title` 포함 |
| `missing required property 'body/@odata.id'` | 중첩 JSON이 아니라 `/`로 평탄화된 키 사용 |
| `ApiOperationNotFound` | operation ID 추측 — `search_operations` 사용 |
| `InvalidApprovalType` | `CustomResponse`, 단수형 |
| `connection reference … could not be found` | solution flow에 `update_flow` 시도 — 삭제 후 재생성 |

## 런타임 에러

| 에러 | 해결 |
|---|---|
| `Unexpected segment DynamicPathSegment` | Graph URL이 아니라 GUID만 |
| `addMinutes`/`addDays` 표현식 실패 | 인자는 **정수**여야 함 |
| Switch가 항상 default로 감 | Choice 컬럼은 `.../Value`로 읽기 |
| 빈 배열 인덱스 | lookup을 방어하세요 — DEFAULT 대체 행 추가 |

## 동작 관련

| 증상 | 해결 |
|---|---|
| `publish_flow`는 성공인데 상태가 `Stopped` | `list_flows`로 확인, 서버 로그 읽기 |
| `Started`인데 실행이 없음 | 첫 폴링 최대 1시간. 그리고 trigger는 **생성 시에만** 동작 |
| agent가 행동 없이 서술만 함 | **Esc**, 가드레일 prompt 재입력 |

---

# 부록 B — Skill 레퍼런스

Copilot CLI에서 슬래시 명령으로 실행합니다.

| Skill | 사용 시점 | 오늘 사용 위치 |
|---|---|---|
| `/setup` | 최초 사전 점검, 또는 뭔가 고장났을 때 | Part 1.7 |
| `/browse-flows` | environment와 flow 탐색 | Part 2.2 |
| `/create-flow` | 대화형 flow 생성 | Scenario 1 |
| `/build-flow` | 설명만으로 자율 생성 | Scenario 2 |
| `/debug-flow` | 실패한 실행 대화형 디버깅 | Scenario 1 의도된 실패 |
| `/diagnose-flow` | 실행에 대한 자율 심층 진단 | Scenario 1 의도된 실패 |
| `/manage-flows` | publish, test, 일괄 작업, 인벤토리 | Part 7 |
| `/manage-desktop-flows` | Desktop / RPA flow, machine group | 오늘은 사용 안 함 |
| `/route-environments` | environment 확인 및 라우팅 | environment가 잘못됐을 때 |

**Skill 아래에는 56개의 MCP tool이 있습니다.** 이름을 알아둘 만한 것들:

| Tool | 역할 |
|---|---|
| `set_current_env` | 이 세션의 environment 고정 |
| `pick_or_create_connection` | Connected 상태 connection을 멱등적으로 확보 |
| `resolve_entity` | 표시 이름 → GUID, 신뢰도 점수 포함 |
| `list_datasets` / `list_tables` | SharePoint 사이트와 리스트 |
| `search_operations` / `get_connector` | 실제 operation ID 찾기 |
| `resolve_params` | operation의 정확한 파라미터 이름 |
| `invoke_operation` | connector의 동적 확인자 호출 (예: 유효한 enum 값) |
| `validate_flow` / `preflight_flow` | 저장 전 오류 탐지 |
| `create_flow` / `publish_flow` | 생성 및 활성화 |
| `get_run_history` / `get_run_actions` / `diagnose_run` | 무슨 일이 있었는지 읽기 |
| `edit_flow` | 전체 정의 재전송 없이 부분 수정 |
| `get_expression_help` | Power Automate 표현식 함수 조회 |

---

# 부록 C — 내 환경 카드

**Part 1에서 채워 넣으세요. 하루 종일 사용합니다.**

| 항목 | 값 |
|---|---|
| **내 이름 접미사** | `_______________________` |
| Tenant ID | `_______________________` |
| Environment 이름 | `_______________________` |
| Environment ID | `_______________________` |
| SharePoint 사이트 URL | `_______________________` |
| Teams team `Contoso` groupId | `_______________________` |
| Teams channel `IT-Ops` channelId | `_______________________` |
| 내 이메일 (승인용) | `_______________________` |
| 배정받은 demo requester | `_______________________` |

**SharePoint 리스트 GUID** *(Part 2.3의 resolve 결과 또는 xlsx의 `Environment-Reference` 시트)*

| List | GUID |
|---|---|
| IT-Requests | `_______________________` |
| Routing-Table | `_______________________` |
| Flow-Health-Log | `_______________________` |
| Privileged-Groups | `_______________________` |
| Access-Requests | `_______________________` |

**내 flow**

| Scenario | Flow 이름 | Flow ID | 상태 |
|---|---|---|---|
| S1 | HOL S1 — IT Request Triage — ______ | ____________ | ______ |
| S2 | HOL S2 — Flow Health Guardian — ______ | ____________ | ______ |
| S3 | HOL S3 — Access Request Provisioner — ______ | ____________ | ______ |

---

### 회사로 가져갈 두 가지

1. **모델을 고정하고, 가드레일 prompt를 붙여넣으세요.** 나머지는 대부분 복구 가능합니다.
2. **존재하지 않는 것은 비슷한 걸로 대체하지 말고 그렇다고 말해달라고 agent에게 요청하세요.**
   문장 하나면 됩니다. 깔끔하게 저장되고 운영에서 죽는 flow를 막아주는 가장 저렴한 보호 장치입니다.
