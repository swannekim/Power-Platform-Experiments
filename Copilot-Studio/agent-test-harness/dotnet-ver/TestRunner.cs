// TestRunner.cs — orchestrates functional, latency, load, and quality runs.

using System.Diagnostics;
using System.Text.RegularExpressions;

namespace AgentTestHarness;

public static class TestRunner
{
    // ---- Assertion evaluation -------------------------------------------
    public static List<CheckResult> Evaluate(ExpectSpec? expect, string reply, Turn turn)
    {
        var checks = new List<CheckResult>();
        if (expect is null) return checks;
        var low = reply.ToLowerInvariant();

        if (expect.ContainsAny is { Count: > 0 } any)
        {
            var hit = any.Where(n => low.Contains(n.ToLowerInvariant())).ToList();
            checks.Add(new CheckResult
            {
                Check = $"contains any of [{string.Join(", ", any)}]",
                Passed = hit.Count > 0,
                Detail = hit.Count > 0 ? $"matched [{string.Join(", ", hit)}]" : "no expected phrase found",
            });
        }
        if (expect.ContainsAll is { Count: > 0 } all)
        {
            var missing = all.Where(n => !low.Contains(n.ToLowerInvariant())).ToList();
            checks.Add(new CheckResult
            {
                Check = $"contains all of [{string.Join(", ", all)}]",
                Passed = missing.Count == 0,
                Detail = missing.Count == 0 ? "all present" : $"missing [{string.Join(", ", missing)}]",
            });
        }
        if (expect.NotContains is { Count: > 0 } no)
        {
            var bad = no.Where(n => low.Contains(n.ToLowerInvariant())).ToList();
            checks.Add(new CheckResult
            {
                Check = $"must not contain [{string.Join(", ", no)}]",
                Passed = bad.Count == 0,
                Detail = bad.Count == 0 ? "clean" : $"found forbidden [{string.Join(", ", bad)}]",
            });
        }
        if (!string.IsNullOrEmpty(expect.Regex))
        {
            bool ok = Regex.IsMatch(reply, expect.Regex, RegexOptions.IgnoreCase);
            checks.Add(new CheckResult { Check = $"regex /{expect.Regex}/", Passed = ok, Detail = ok ? "matched" : "no match" });
        }
        if (expect.HasCard)
        {
            checks.Add(new CheckResult
            {
                Check = "returns a rich card / attachment",
                Passed = turn.HasCard,
                Detail = turn.HasCard ? "card present" : "no attachment",
            });
        }
        if (expect.MaxResponseS is double budget)
        {
            double actual = turn.Timings.ReceiveResponse;
            checks.Add(new CheckResult
            {
                Check = $"responds within {budget}s",
                Passed = actual <= budget,
                Detail = $"took {actual:F2}s",
            });
        }
        return checks;
    }

    // ---- Functional + latency -------------------------------------------
    public static async Task<CaseResult> RunCaseAsync(TestCase c, Func<DirectLineClient> factory)
    {
        var result = new CaseResult
        {
            Id = c.Id,
            Name = string.IsNullOrEmpty(c.Name) ? c.Id : c.Name,
            Category = string.IsNullOrEmpty(c.Category) ? "Uncategorised" : c.Category,
        };
        try
        {
            var client = factory();
            await client.StartAsync();
            var steps = c.Steps ?? new List<Step> { new() { Send = c.Send ?? "", Expect = c.Expect } };
            foreach (var step in steps)
            {
                var turn = await client.SendAsync(step.Send);
                result.Latencies.Add(turn.Timings.ReceiveResponse);
                result.Turns.Add(new TurnResult
                {
                    User = step.Send,
                    Bot = turn.CombinedReply,
                    ResponseS = Math.Round(turn.Timings.ReceiveResponse, 3),
                });
                result.Checks.AddRange(Evaluate(step.Expect, turn.CombinedReply, turn));
            }
        }
        catch (Exception e)   // network / auth / agent failure
        {
            result.Error = $"{e.GetType().Name}: {e.Message}";
        }

        result.Passed = result.Error is null && result.Checks.All(ch => ch.Passed);
        return result;
    }

    // ---- Load / performance — N concurrent conversations ----------------
    public static async Task<LoadResult> RunLoadAsync(int concurrency, Func<DirectLineClient> factory, string message = "hi")
    {
        var sw = Stopwatch.StartNew();
        var tasks = Enumerable.Range(0, concurrency).Select(async _ =>
        {
            try
            {
                var c = factory();
                await c.StartAsync();
                var t = await c.SendAsync(message);
                return (double?)t.Timings.ReceiveResponse;
            }
            catch
            {
                return (double?)null;
            }
        });
        var outcomes = await Task.WhenAll(tasks);
        sw.Stop();

        var lat = outcomes.Where(x => x.HasValue).Select(x => x!.Value).OrderBy(x => x).ToList();
        double wall = sw.Elapsed.TotalSeconds;

        double Pct(int p) => lat.Count == 0
            ? 0
            : lat[Math.Min(lat.Count - 1, (int)Math.Round(p / 100.0 * (lat.Count - 1)))];

        return new LoadResult
        {
            Concurrency = concurrency,
            Completed = lat.Count,
            Errors = outcomes.Count(x => !x.HasValue),
            WallClockS = Math.Round(wall, 2),
            ThroughputConvosPerS = wall > 0 ? Math.Round(lat.Count / wall, 2) : 0,
            P50S = Math.Round(Pct(50), 2),
            P95S = Math.Round(Pct(95), 2),
            MaxS = lat.Count > 0 ? Math.Round(lat.Max(), 2) : 0,
            MeanS = lat.Count > 0 ? Math.Round(lat.Average(), 2) : 0,
        };
    }

    // ---- Optional: answer-quality via LLM-as-judge (stub) ---------------
    // Plug in whatever model you already use (Azure OpenAI, etc.). Keep the
    // judge prompt strict and rubric-based. Returns a neutral placeholder so
    // the pipeline runs end-to-end until you wire in a real model call.
    public static QualityResult JudgeQuality(TestCase c, string reply) => new()
    {
        Id = c.Id,
        Name = c.Name,
        Scored = false,
        Score = null,
        Note = "LLM judge not configured — see JudgeQuality() in TestRunner.cs",
    };
}
