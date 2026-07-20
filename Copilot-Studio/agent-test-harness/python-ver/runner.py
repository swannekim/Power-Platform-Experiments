"""
runner.py — the test orchestrator
---------------------------------
Loads test_cases.yaml, runs each case against the agent through Direct Line,
evaluates the assertions, and (optionally) runs a small load test and an
LLM-as-judge answer-quality pass. Writes results.json, then hands off to
report.py to produce the Markdown report.

Usage:
    python runner.py                      # functional + latency
    python runner.py --load 10            # also run 10 concurrent conversations
    python runner.py --judge              # also score 'quality' cases with an LLM
    python runner.py --report README.md   # where to write the Markdown report

Configuration comes from environment variables (so secrets never live in code):
    DIRECTLINE_TOKEN_ENDPOINT   the token endpoint URL from Copilot Studio, OR
    DIRECTLINE_SECRET           a Direct Line secret
    DIRECTLINE_BASE             (optional) override the regional Direct Line host
    AGENT_NAME                  (optional) friendly name shown in the report
"""

from __future__ import annotations

import os
import re
import sys
import json
import time
import argparse
import statistics
import concurrent.futures as cf

import yaml

from directline_client import DirectLineClient
import report as report_mod


def make_client() -> DirectLineClient:
    return DirectLineClient(
        token_endpoint=os.environ.get("DIRECTLINE_TOKEN_ENDPOINT"),
        secret=os.environ.get("DIRECTLINE_SECRET"),
        directline_base=os.environ.get(
            "DIRECTLINE_BASE",
            "https://directline.botframework.com/v3/directline",
        ),
    )


# ---------------------------------------------------------------------------
# Assertion evaluation
# ---------------------------------------------------------------------------
def evaluate(expect: dict, reply: str, turn) -> list[dict]:
    """Return a list of {check, passed, detail} for one turn."""
    checks: list[dict] = []
    low = reply.lower()

    if "contains_any" in expect:
        needles = expect["contains_any"]
        hit = [n for n in needles if n.lower() in low]
        checks.append({
            "check": f"contains any of {needles}",
            "passed": bool(hit),
            "detail": f"matched {hit}" if hit else "no expected phrase found",
        })
    if "contains_all" in expect:
        needles = expect["contains_all"]
        missing = [n for n in needles if n.lower() not in low]
        checks.append({
            "check": f"contains all of {needles}",
            "passed": not missing,
            "detail": "all present" if not missing else f"missing {missing}",
        })
    if "not_contains" in expect:
        bad = [n for n in expect["not_contains"] if n.lower() in low]
        checks.append({
            "check": f"must not contain {expect['not_contains']}",
            "passed": not bad,
            "detail": "clean" if not bad else f"found forbidden {bad}",
        })
    if "regex" in expect:
        ok = re.search(expect["regex"], reply, re.IGNORECASE) is not None
        checks.append({
            "check": f"regex /{expect['regex']}/",
            "passed": ok,
            "detail": "matched" if ok else "no match",
        })
    if expect.get("has_card"):
        checks.append({
            "check": "returns a rich card / attachment",
            "passed": turn.has_card,
            "detail": "card present" if turn.has_card else "no attachment",
        })
    if "max_response_s" in expect:
        budget = float(expect["max_response_s"])
        actual = turn.timings.receive_response
        checks.append({
            "check": f"responds within {budget}s",
            "passed": actual <= budget,
            "detail": f"took {actual:.2f}s",
        })
    return checks


# ---------------------------------------------------------------------------
# Functional + latency run
# ---------------------------------------------------------------------------
def run_case(case: dict) -> dict:
    client = make_client()
    session = client.start()
    result = {
        "id": case["id"],
        "name": case.get("name", case["id"]),
        "category": case.get("category", "Uncategorised"),
        "turns": [],
        "checks": [],
        "latencies": [],
        "error": None,
    }
    try:
        steps = case.get("steps") or [{"send": case["send"], "expect": case.get("expect", {})}]
        for step in steps:
            turn = client.send(step["send"])
            result["latencies"].append(turn.timings.receive_response)
            result["turns"].append({
                "user": step["send"],
                "bot": turn.combined_reply,
                "response_s": round(turn.timings.receive_response, 3),
            })
            result["checks"].extend(evaluate(step.get("expect", {}), turn.combined_reply, turn))
    except Exception as e:  # network / auth / agent failure
        result["error"] = f"{type(e).__name__}: {e}"

    result["passed"] = (result["error"] is None) and all(c["passed"] for c in result["checks"])
    result["session_timings"] = session.as_dict()
    return result


# ---------------------------------------------------------------------------
# Load / performance run — N concurrent conversations of one simple message
# ---------------------------------------------------------------------------
def run_load(concurrency: int, message: str = "hi") -> dict:
    def one():
        c = make_client()
        c.start()
        t = c.send(message)
        return t.timings.receive_response

    t0 = time.monotonic()
    latencies: list[float] = []
    errors = 0
    with cf.ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(one) for _ in range(concurrency)]
        for f in cf.as_completed(futures):
            try:
                latencies.append(f.result())
            except Exception:
                errors += 1
    wall = time.monotonic() - t0

    latencies.sort()
    def pct(p):
        if not latencies:
            return 0.0
        k = min(len(latencies) - 1, int(round((p / 100) * (len(latencies) - 1))))
        return latencies[k]

    return {
        "concurrency": concurrency,
        "completed": len(latencies),
        "errors": errors,
        "wall_clock_s": round(wall, 2),
        "throughput_convos_per_s": round(len(latencies) / wall, 2) if wall else 0,
        "p50_s": round(pct(50), 2),
        "p95_s": round(pct(95), 2),
        "max_s": round(max(latencies), 2) if latencies else 0,
        "mean_s": round(statistics.mean(latencies), 2) if latencies else 0,
    }


# ---------------------------------------------------------------------------
# Optional: answer-quality via LLM-as-judge (stub — wire to your LLM of choice)
# ---------------------------------------------------------------------------
def judge_quality(case: dict, reply: str) -> dict | None:
    """Score the agent's answer 1–5 against an expected answer.

    This is a STUB. Plug in whatever model you already use (Azure OpenAI,
    the Anthropic API, etc.). Keep the judge prompt strict and rubric-based.
    """
    q = case.get("quality")
    if not q:
        return None
    # --- Replace the block below with a real model call. -------------------
    # Example shape of a real call:
    #   score = call_your_llm(system=RUBRIC, user=f"Expected:\n{q['expected_answer']}\n\nActual:\n{reply}")
    # For now we return a neutral placeholder so the pipeline runs end-to-end.
    return {
        "scored": False,
        "score": None,
        "expected": q["expected_answer"].strip(),
        "note": "LLM judge not configured — see judge_quality() in runner.py",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", default="test_cases.yaml")
    ap.add_argument("--load", type=int, default=0, help="run N concurrent conversations")
    ap.add_argument("--judge", action="store_true", help="score 'quality' cases with an LLM")
    ap.add_argument("--report", default="README.md")
    ap.add_argument("--results", default="results.json")
    args = ap.parse_args()

    if not (os.environ.get("DIRECTLINE_TOKEN_ENDPOINT") or os.environ.get("DIRECTLINE_SECRET")):
        sys.exit("ERROR: set DIRECTLINE_TOKEN_ENDPOINT or DIRECTLINE_SECRET first (see SETUP.md).")

    with open(args.cases, encoding="utf-8") as f:
        cases = yaml.safe_load(f)

    print(f"Running {len(cases)} functional cases...")
    results = [run_case(c) for c in cases]
    for r in results:
        print(f"  [{'PASS' if r['passed'] else 'FAIL'}] {r['id']}")

    quality = []
    if args.judge:
        print("Scoring answer quality...")
        for c in cases:
            if c.get("quality"):
                # re-send once for a clean quality read
                client = make_client(); client.start()
                reply = client.send(c["send"]).combined_reply
                quality.append({"id": c["id"], "name": c.get("name"),
                                **(judge_quality(c, reply) or {})})

    load = run_load(args.load) if args.load else None

    payload = {
        "agent_name": os.environ.get("AGENT_NAME", "Copilot Studio Agent"),
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
        "functional": results,
        "load": load,
        "quality": quality,
    }
    with open(args.results, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    report_mod.write_report(payload, args.report)
    print(f"Report written to {args.report}")

    # Non-zero exit if anything failed, so CI marks the run red.
    if any(not r["passed"] for r in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
