# Setup — Copilot Studio agent test harness (.NET / C#)

This is the **C#/.NET** port of the Direct Line test harness. It tests a
**Microsoft Copilot Studio** agent the same way a real user would — over the
**Direct Line API** — and publishes a Markdown report to your repo's `README.md`.
It's a functional twin of the Python version; pick whichever your team prefers.

| Dimension | What it answers | Where |
|---|---|---|
| **Functional** | Does each feature/topic actually work? | `test_cases.yaml` assertions |
| **Latency** | How fast does the agent respond? | timed on every turn |
| **Load / performance** | How does it hold up under concurrency? | `--load N` |
| **Answer quality** | Is the answer correct & complete? | optional LLM judge |

## How it works (the 4-step Direct Line flow)

1. **Get a token** — from your agent's Direct Line *token endpoint* (or a secret).
2. **Start a conversation** — returns a `conversationId`.
3. **Send the user message** — HTTP POST (this just confirms receipt).
4. **Poll for the reply** — HTTP GET until the agent goes quiet; the response
   time is *user message → agent's last reply*, the latency a user actually feels.

> Mirrors Microsoft's guidance, *"Test conversational agents using Direct Line."*
> Copilot Studio has no explicit "last message" signal, so the harness treats a
> short quiet period (or an `acceptingInput` hint) as end-of-turn.

## Prerequisites

- [.NET SDK 8.0+](https://dotnet.microsoft.com/download)

## 1. Turn on Direct Line for your agent

1. In **Copilot Studio**, open your agent → **Publish** it at least once.
2. Go to **Settings → Security → Web channel security** (or **Channels → Mobile app**).
3. Copy the **Token Endpoint** URL. A GET against it returns a Direct Line token.
   (Alternatively, copy a **Direct Line secret** if your setup uses one.)

## 2. Configure credentials

**Locally** — set environment variables (never commit secrets):

```bash
export DIRECTLINE_TOKEN_ENDPOINT="https://...token endpoint from step 1..."
# or:  export DIRECTLINE_SECRET="your-direct-line-secret"
export AGENT_NAME="My Support Agent"     # optional, shown in the report
```

On Windows PowerShell:

```powershell
$env:DIRECTLINE_TOKEN_ENDPOINT = "https://..."
$env:AGENT_NAME = "My Support Agent"
```

**In GitHub** — repo **Settings → Secrets and variables → Actions**:
- Secret `DIRECTLINE_TOKEN_ENDPOINT` (or `DIRECTLINE_SECRET`)
- Variable `AGENT_NAME` (optional)

> Regional Direct Line host? Also set `DIRECTLINE_BASE`
> (e.g. `https://europe.directline.botframework.com/v3/directline`).

## 3. Run it locally

```bash
dotnet run                        # functional + latency → writes README.md
dotnet run -- --load 10           # also run 10 concurrent conversations
dotnet run -- --judge             # also score 'quality' cases (needs an LLM wired in)
dotnet run -- --report README.md  # choose the report path
```

The first run restores the one NuGet dependency (YamlDotNet) and builds
automatically. Open the generated `README.md` to see the report.

## 4. Automate it on GitHub

`.github/workflows/agent-tests.yml` already:
- runs **on a daily schedule**, **on demand**, and **on push**,
- executes the suite (with a light load test),
- commits the fresh report back to `README.md`.

Adjust the `cron:` line for your cadence and the `--load N` value for CI.

## 5. Write your own tests

Edit `test_cases.yaml`. Each case sends a message (or a multi-turn conversation)
and asserts on the reply — `contains_any`, `not_contains` (great for catching
"I didn't understand" fallbacks), `has_card`, `max_response_s`, and more. See the
comments at the top of that file.

## 6. Wire up the LLM judge (optional)

`TestRunner.JudgeQuality()` is a stub that returns a neutral placeholder. Replace
its body with a call to your model (Azure OpenAI, etc.), scoring the agent's reply
1–5 against `quality.expected_answer`. Keep the judge prompt strict and rubric-based.

## Scaling up the load test

The built-in `--load` runner is fine for a CI concurrency smoke-test. For serious
load (hundreds/thousands of virtual users), point **Azure Load Testing** or
**JMeter** at the same Direct Line endpoints — Microsoft recommends WebSocket-based
scripts for high-fidelity load. `DirectLineClient.cs` is a faithful reference for
the request flow those tools replicate.

## Files

```
Program.cs             entry point: config, arg parsing, orchestration
DirectLineClient.cs    Direct Line client (token, conversation, send, receive, timing)
TestRunner.cs          functional + latency + load + quality logic
ReportGenerator.cs     renders the payload → Markdown (README.md)
Models.cs              config + result models
test_cases.yaml        your test suite (edit this)
AgentTestHarness.csproj project file (net8.0, YamlDotNet)
.github/workflows/     GitHub Actions automation
```
