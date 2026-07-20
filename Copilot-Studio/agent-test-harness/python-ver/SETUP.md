# Setup — Copilot Studio agent test harness (Direct Line)

This project tests a **Microsoft Copilot Studio** agent the same way a real user
would talk to it — over the **Direct Line API** — and publishes a Markdown report
to your repo's `README.md`. It covers four things:

| Dimension | What it answers | Where |
|---|---|---|
| **Functional** | Does each feature/topic actually work? | `test_cases.yaml` assertions |
| **Latency** | How fast does the agent respond? | timed on every turn |
| **Load / performance** | How does it hold up under concurrency? | `runner.py --load N` |
| **Answer quality** | Is the answer correct & complete? | optional LLM judge |

## How it works (the 4-step Direct Line flow)

1. **Get a token** — from your agent's Direct Line *token endpoint* (or a secret).
2. **Start a conversation** — returns a `conversationId`.
3. **Send the user message** — HTTP POST (this just confirms receipt).
4. **Poll for the reply** — HTTP GET until the agent goes quiet; the response
   time is *user message → agent's last reply*, which is what users actually feel.

> This mirrors Microsoft's official guidance, *"Test conversational agents using
> Direct Line."* Copilot Studio has no explicit "last message" signal, so the
> harness treats a short quiet period (or an `acceptingInput` hint) as end-of-turn.

## 1. Turn on Direct Line for your agent

1. In **Copilot Studio**, open your agent → **Publish** it at least once.
2. Go to **Settings → Security → Web channel security** (or **Channels → Mobile app**).
3. Copy the **Token Endpoint** URL. That single URL is all the harness needs —
   a GET against it returns a Direct Line token. (Alternatively, copy a
   **Direct Line secret** if your setup uses one.)

## 2. Configure credentials

**Locally** — set environment variables (never commit secrets):

```bash
export DIRECTLINE_TOKEN_ENDPOINT="https://...token endpoint from step 1..."
# or:  export DIRECTLINE_SECRET="your-direct-line-secret"
export AGENT_NAME="My Support Agent"     # optional, shown in the report
```

**In GitHub** — repo **Settings → Secrets and variables → Actions**:
- Secret `DIRECTLINE_TOKEN_ENDPOINT` (or `DIRECTLINE_SECRET`)
- Variable `AGENT_NAME` (optional)

> If your tenant uses a regional Direct Line host, also set
> `DIRECTLINE_BASE` (e.g. `https://europe.directline.botframework.com/v3/directline`).

## 3. Run it locally

```bash
pip install -r requirements.txt
python runner.py                 # functional + latency → writes README.md
python runner.py --load 10       # also run 10 concurrent conversations
python runner.py --judge         # also score 'quality' cases (needs an LLM wired in)
```

Open the generated `README.md` to see the report.

## 4. Automate it on GitHub

`.github/workflows/agent-tests.yml` already:
- runs **on a daily schedule**, **on demand**, and **on push**,
- executes the suite (with a light load test),
- commits the fresh report back to `README.md`.

Adjust the `cron:` line for your cadence and the `--load N` value for how hard
you want to push it in CI.

## 5. Write your own tests

Edit `test_cases.yaml`. Each case sends a message (or a multi-turn
conversation) and asserts on the reply — `contains_any`, `not_contains`
(great for catching "I didn't understand" fallbacks), `has_card`,
`max_response_s`, and more. See the comments at the top of that file.

## Scaling up the load test

The built-in `--load` runner is fine for a quick concurrency check in CI. For
serious load testing (hundreds/thousands of virtual users), point **Azure Load
Testing** or **JMeter** at the same Direct Line endpoints — Microsoft's guidance
recommends WebSocket-based scripts for high-fidelity load. The `directline_client.py`
here is a faithful reference for the request flow those tools need to replicate.

## Files

```
directline_client.py   Direct Line client (token, conversation, send, receive, timing)
test_cases.yaml        your test suite (edit this)
runner.py              orchestrates functional + latency + load + quality
report.py              renders results.json → Markdown (README.md)
requirements.txt       Python deps
.github/workflows/     GitHub Actions automation
```
