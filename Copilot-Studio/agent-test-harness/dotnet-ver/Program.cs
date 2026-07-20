// Program.cs — entry point. Reads config from environment variables, loads the
// YAML test suite, runs functional + latency (+ optional load + quality), writes
// results.json, and renders the Markdown report.
//
//   dotnet run                         functional + latency
//   dotnet run -- --load 10            also run 10 concurrent conversations
//   dotnet run -- --judge              also score 'quality' cases with an LLM
//   dotnet run -- --report README.md   where to write the Markdown report
//
// Config (so secrets never live in code):
//   DIRECTLINE_TOKEN_ENDPOINT   token endpoint URL from Copilot Studio, OR
//   DIRECTLINE_SECRET           a Direct Line secret
//   DIRECTLINE_BASE             (optional) override the regional Direct Line host
//   AGENT_NAME                  (optional) friendly name shown in the report

using System.Globalization;
using System.Text.Json;
using AgentTestHarness;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

// Keep numbers formatted with '.' decimals regardless of the CI machine locale.
CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var opts = Cli.Parse(args);

var tokenEndpoint = Environment.GetEnvironmentVariable("DIRECTLINE_TOKEN_ENDPOINT");
var secret = Environment.GetEnvironmentVariable("DIRECTLINE_SECRET");
var dlBase = Environment.GetEnvironmentVariable("DIRECTLINE_BASE")
             ?? "https://directline.botframework.com/v3/directline";
var agentName = Environment.GetEnvironmentVariable("AGENT_NAME") ?? "Copilot Studio Agent";

if (string.IsNullOrEmpty(tokenEndpoint) && string.IsNullOrEmpty(secret))
{
    Console.Error.WriteLine("ERROR: set DIRECTLINE_TOKEN_ENDPOINT or DIRECTLINE_SECRET first (see SETUP.md).");
    return 2;
}

DirectLineClient Factory() => new(tokenEndpoint, secret, dlBase);

var deserializer = new DeserializerBuilder()
    .WithNamingConvention(UnderscoredNamingConvention.Instance)
    .IgnoreUnmatchedProperties()
    .Build();
var cases = deserializer.Deserialize<List<TestCase>>(File.ReadAllText(opts.Cases))
            ?? new List<TestCase>();

Console.WriteLine($"Running {cases.Count} functional cases...");
var results = new List<CaseResult>();
foreach (var c in cases)
{
    var r = await TestRunner.RunCaseAsync(c, Factory);
    results.Add(r);
    Console.WriteLine($"  [{(r.Passed ? "PASS" : "FAIL")}] {r.Id}");
}

var quality = new List<QualityResult>();
if (opts.Judge)
{
    Console.WriteLine("Scoring answer quality...");
    foreach (var c in cases.Where(c => c.Quality is not null))
    {
        var client = Factory();
        await client.StartAsync();
        var reply = (await client.SendAsync(c.Send ?? "")).CombinedReply;
        quality.Add(TestRunner.JudgeQuality(c, reply));
    }
}

LoadResult? load = opts.Load > 0 ? await TestRunner.RunLoadAsync(opts.Load, Factory) : null;

var payload = new ReportPayload
{
    AgentName = agentName,
    GeneratedAt = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss 'UTC'", CultureInfo.InvariantCulture),
    Functional = results,
    Load = load,
    Quality = quality,
};

File.WriteAllText(opts.Results,
    JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
ReportGenerator.WriteReport(payload, opts.Report);
Console.WriteLine($"Report written to {opts.Report}");

// Non-zero exit if anything failed, so CI marks the run red.
return results.Any(r => !r.Passed) ? 1 : 0;


// ---- tiny argument parser -------------------------------------------------
sealed class Options
{
    public string Cases = "test_cases.yaml";
    public int Load;
    public bool Judge;
    public string Report = "README.md";
    public string Results = "results.json";
}

static class Cli
{
    public static Options Parse(string[] args)
    {
        var o = new Options();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--cases": o.Cases = args[++i]; break;
                case "--load": o.Load = int.Parse(args[++i]); break;
                case "--judge": o.Judge = true; break;
                case "--report": o.Report = args[++i]; break;
                case "--results": o.Results = args[++i]; break;
            }
        }
        return o;
    }
}
