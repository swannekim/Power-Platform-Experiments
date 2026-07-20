// DirectLineClient.cs
// -------------------
// Client for talking to a Microsoft Copilot Studio agent over the Direct Line
// API (v3.0) — the same channel the web chat uses. Anything a real user can do,
// this can do, which is what makes it useful for automated testing.
//
// Flow (per Microsoft Learn "Test conversational agents using Direct Line"):
//   1. Get a Direct Line token (from a Copilot Studio token endpoint, or a secret)
//   2. Start a conversation -> conversationId
//   3. Send an activity (the user's message) via HTTP POST
//   4. Poll the activities endpoint (HTTP GET) until the agent finishes replying,
//      timing every step.
//
// We use HTTP GET polling (not WebSockets) because it's deterministic and simple
// for a test harness — the documented fallback that's easy to reason about in CI.

using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace AgentTestHarness;

public sealed class DirectLineClient
{
    // One HttpClient for the whole process. We set the auth header per-request
    // (not on DefaultRequestHeaders) so it's safe to reuse under concurrency.
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };

    private readonly string? _tokenEndpoint;
    private readonly string? _secret;
    private readonly string _base;
    private readonly string _userId;
    private readonly double _quietPeriodS;   // silence that marks end-of-turn
    private readonly double _turnTimeoutS;   // hard ceiling per turn
    private readonly int _pollIntervalMs;

    private string? _token;
    private string? _conversationId;
    private string? _watermark;

    public Timings SessionTimings { get; } = new();

    public DirectLineClient(
        string? tokenEndpoint,
        string? secret,
        string directLineBase = "https://directline.botframework.com/v3/directline",
        string? userId = null,
        double quietPeriodS = 2.5,
        double turnTimeoutS = 45.0,
        int pollIntervalMs = 750)
    {
        if (string.IsNullOrEmpty(tokenEndpoint) && string.IsNullOrEmpty(secret))
            throw new ArgumentException("Provide either tokenEndpoint or secret.");
        _tokenEndpoint = tokenEndpoint;
        _secret = secret;
        _base = directLineBase.TrimEnd('/');
        _userId = userId ?? $"user-{Guid.NewGuid():N}"[..13];
        _quietPeriodS = quietPeriodS;
        _turnTimeoutS = turnTimeoutS;
        _pollIntervalMs = pollIntervalMs;
    }

    private HttpRequestMessage Authed(HttpMethod method, string url)
    {
        var req = new HttpRequestMessage(method, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        return req;
    }

    // ---- 1. token ---------------------------------------------------------
    private async Task<double> GetTokenAsync()
    {
        var sw = Stopwatch.StartNew();
        if (!string.IsNullOrEmpty(_tokenEndpoint))
        {
            // Copilot Studio token endpoint: a plain GET returns a token.
            using var resp = await Http.GetAsync(_tokenEndpoint);
            resp.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            _token = doc.RootElement.GetProperty("token").GetString();
        }
        else
        {
            // Generate a token from a Direct Line secret.
            using var req = new HttpRequestMessage(HttpMethod.Post, $"{_base}/tokens/generate");
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _secret);
            using var resp = await Http.SendAsync(req);
            resp.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            _token = doc.RootElement.GetProperty("token").GetString();
        }
        sw.Stop();
        return sw.Elapsed.TotalSeconds;
    }

    // ---- 2. start conversation -------------------------------------------
    private async Task<double> StartConversationAsync()
    {
        var sw = Stopwatch.StartNew();
        using var req = Authed(HttpMethod.Post, $"{_base}/conversations");
        using var resp = await Http.SendAsync(req);
        resp.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        _conversationId = doc.RootElement.GetProperty("conversationId").GetString();
        sw.Stop();
        return sw.Elapsed.TotalSeconds;
    }

    /// <summary>Get a token and open a conversation. Call once per test session.</summary>
    public async Task<Timings> StartAsync()
    {
        SessionTimings.GenerateToken = await GetTokenAsync();
        SessionTimings.StartConversation = await StartConversationAsync();
        await DrainInitialAsync();   // discard the greeting so it isn't timed as turn 1
        return SessionTimings;
    }

    private async Task DrainInitialAsync()
    {
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < _quietPeriodS + 3)
        {
            var acts = await GetActivitiesAsync();
            if (acts.Any(a => a.TryGetProperty("inputHint", out var h) && h.GetString() == "acceptingInput"))
                break;
            await Task.Delay(_pollIntervalMs);
        }
    }

    // ---- 3. send activity -------------------------------------------------
    private async Task<double> PostActivityAsync(string text)
    {
        var sw = Stopwatch.StartNew();
        var payload = JsonSerializer.Serialize(new
        {
            type = "message",
            from = new { id = _userId },
            text
        });
        using var req = Authed(HttpMethod.Post, $"{_base}/conversations/{_conversationId}/activities");
        req.Content = new StringContent(payload, Encoding.UTF8, "application/json");
        using var resp = await Http.SendAsync(req);
        resp.EnsureSuccessStatusCode();
        sw.Stop();
        return sw.Elapsed.TotalSeconds;
    }

    // ---- 4. receive activities -------------------------------------------
    private async Task<List<JsonElement>> GetActivitiesAsync()
    {
        var url = $"{_base}/conversations/{_conversationId}/activities";
        if (!string.IsNullOrEmpty(_watermark)) url += $"?watermark={_watermark}";

        using var req = Authed(HttpMethod.Get, url);
        using var resp = await Http.SendAsync(req);
        resp.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        var root = doc.RootElement;

        if (root.TryGetProperty("watermark", out var wm) && wm.ValueKind == JsonValueKind.String)
            _watermark = wm.GetString();

        var list = new List<JsonElement>();
        if (root.TryGetProperty("activities", out var acts) && acts.ValueKind == JsonValueKind.Array)
            foreach (var a in acts.EnumerateArray())
                list.Add(a.Clone());   // clone: detach from the JsonDocument we dispose
        return list;
    }

    /// <summary>
    /// Send one user message and collect the agent's full reply for this turn.
    /// Response time is measured from just after we POST the user message to the
    /// moment the agent goes quiet — the user-perceived latency.
    /// </summary>
    public async Task<Turn> SendAsync(string text)
    {
        var turn = new Turn { UserText = text };
        turn.Timings.SendActivity = await PostActivityAsync(text);

        var sw = Stopwatch.StartNew();
        double? lastBotAt = null;
        bool acceptingInput = false;

        while (sw.Elapsed.TotalSeconds < _turnTimeoutS && !acceptingInput)
        {
            foreach (var a in await GetActivitiesAsync())
            {
                bool isBot = a.TryGetProperty("from", out var from)
                             && from.TryGetProperty("role", out var role)
                             && role.GetString() == "bot";
                string? type = a.TryGetProperty("type", out var t) ? t.GetString() : null;
                if (isBot && type == "message")
                {
                    turn.BotActivities.Add(a);
                    if (a.TryGetProperty("text", out var txt)
                        && txt.ValueKind == JsonValueKind.String
                        && !string.IsNullOrEmpty(txt.GetString()))
                    {
                        turn.BotMessages.Add(txt.GetString()!);
                    }
                    lastBotAt = sw.Elapsed.TotalSeconds;
                    if (a.TryGetProperty("inputHint", out var hint) && hint.GetString() == "acceptingInput")
                        acceptingInput = true;   // explicit "your turn" -> agent is done
                }
            }

            // Agent has spoken and then gone quiet -> treat the turn as complete.
            if (lastBotAt is double last && (sw.Elapsed.TotalSeconds - last) >= _quietPeriodS)
                break;
            if (acceptingInput) break;
            await Task.Delay(_pollIntervalMs);
        }

        turn.Timings.ReceiveResponse = lastBotAt ?? _turnTimeoutS;
        return turn;
    }
}
