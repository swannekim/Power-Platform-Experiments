// Models.cs — configuration models (parsed from test_cases.yaml),
// client-facing types (Timings, Turn), and result/report models.

using System.Text.Json;
using System.Text.Json.Serialization;

namespace AgentTestHarness;

// ---------------------------------------------------------------------------
// Test-case config (deserialised from test_cases.yaml, underscored_naming)
// ---------------------------------------------------------------------------
public sealed class TestCase
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "Uncategorised";
    public string? Send { get; set; }
    public List<Step>? Steps { get; set; }
    public ExpectSpec? Expect { get; set; }
    public QualitySpec? Quality { get; set; }
}

public sealed class Step
{
    public string Send { get; set; } = "";
    public ExpectSpec? Expect { get; set; }
}

public sealed class ExpectSpec
{
    public List<string>? ContainsAny { get; set; }   // contains_any
    public List<string>? ContainsAll { get; set; }   // contains_all
    public List<string>? NotContains { get; set; }   // not_contains
    public string? Regex { get; set; }               // regex
    public bool HasCard { get; set; }                // has_card
    public double? MaxResponseS { get; set; }        // max_response_s
}

public sealed class QualitySpec
{
    public string ExpectedAnswer { get; set; } = ""; // expected_answer
    public string Note { get; set; } = "";           // note
}

// ---------------------------------------------------------------------------
// Client-facing types
// ---------------------------------------------------------------------------
public sealed class Timings
{
    // Per-step latency in seconds — the numbers Microsoft's guidance says to track.
    public double GenerateToken { get; set; }
    public double StartConversation { get; set; }
    public double SendActivity { get; set; }
    public double ReceiveResponse { get; set; } // user message -> agent's LAST reply
}

public sealed class Turn
{
    public string UserText { get; set; } = "";
    public List<string> BotMessages { get; } = new();

    // Raw agent activities for this turn (cloned so they outlive the HTTP read).
    [JsonIgnore] public List<JsonElement> BotActivities { get; } = new();

    public Timings Timings { get; } = new();

    // All the agent's texts joined — handy for keyword / contains assertions.
    public string CombinedReply =>
        string.Join("\n", BotMessages.Where(m => !string.IsNullOrEmpty(m)));

    public bool HasCard => BotActivities.Any(a =>
        a.TryGetProperty("attachments", out var att)
        && att.ValueKind == JsonValueKind.Array
        && att.GetArrayLength() > 0);
}

// ---------------------------------------------------------------------------
// Result / report models (serialised to results.json)
// ---------------------------------------------------------------------------
public sealed class CheckResult
{
    public string Check { get; set; } = "";
    public bool Passed { get; set; }
    public string Detail { get; set; } = "";
}

public sealed class TurnResult
{
    public string User { get; set; } = "";
    public string Bot { get; set; } = "";
    public double ResponseS { get; set; }
}

public sealed class CaseResult
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public List<TurnResult> Turns { get; set; } = new();
    public List<CheckResult> Checks { get; set; } = new();
    public List<double> Latencies { get; set; } = new();
    public string? Error { get; set; }
    public bool Passed { get; set; }
}

public sealed class LoadResult
{
    public int Concurrency { get; set; }
    public int Completed { get; set; }
    public int Errors { get; set; }
    public double WallClockS { get; set; }
    public double ThroughputConvosPerS { get; set; }
    public double P50S { get; set; }
    public double P95S { get; set; }
    public double MaxS { get; set; }
    public double MeanS { get; set; }
}

public sealed class QualityResult
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public bool Scored { get; set; }
    public int? Score { get; set; }
    public string Note { get; set; } = "";
}

public sealed class ReportPayload
{
    public string AgentName { get; set; } = "";
    public string GeneratedAt { get; set; } = "";
    public List<CaseResult> Functional { get; set; } = new();
    public LoadResult? Load { get; set; }
    public List<QualityResult> Quality { get; set; } = new();
}
