using System.Text;
using System.Text.Json;

namespace RemoteTool.Core.Config;

/// <summary>
/// Per-organization branding baked into the exe at build time (see scripts/build-wizard.ps1 and docs/BRANDING.md).
/// JSON: <c>{"organization":"Acme","maxConcurrentUsers":25,"developedBy":"Toolveriq"}</c>. A missing/broken file yields <see cref="Default"/>.
/// <see cref="RelayLocked"/>: the relay settings baked into the exe are enforced and hidden from the user. <see cref="MaxConcurrentUsers"/> 0 = unlimited. The limit is enforced by the organization's relay (MaxConcurrentSessions); the exe only displays it.
/// </summary>
public sealed record Branding(string Organization, int MaxConcurrentUsers, string DevelopedBy, bool RelayLocked = false)
{
    public const string DefaultDeveloper = "Toolveriq";
    public const int MaxUsersLimit = 100_000;
    public static readonly Branding Default = new("", 0, DefaultDeveloper);

    public static Branding Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Default;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var r = doc.RootElement;
            string Str(string n) => r.TryGetProperty(n, out var p) && p.ValueKind == JsonValueKind.String ? Clean(p.GetString()) : "";
            var users = r.TryGetProperty("maxConcurrentUsers", out var u) && u.ValueKind == JsonValueKind.Number && u.TryGetInt32(out var n) ? Math.Clamp(n, 0, MaxUsersLimit) : 0;
            var dev = Str("developedBy");
            var locked = r.TryGetProperty("relayLocked", out var rl) && rl.ValueKind == JsonValueKind.True;
            return new Branding(Str("organization"), users, dev.Length > 0 ? dev : DefaultDeveloper, locked);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return Default; }   // broken branding must never stop the app
    }

    /// <summary>Trims, drops control characters and caps the length (the name is shown in window text and written to logs).</summary>
    public static string Clean(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder();
        foreach (var ch in s.Trim()) if (!char.IsControl(ch)) sb.Append(ch);
        return sb.Length > 80 ? sb.ToString(0, 80) : sb.ToString();
    }

    public string ToJson() => JsonSerializer.Serialize(new { organization = Organization, maxConcurrentUsers = MaxConcurrentUsers, developedBy = DevelopedBy, relayLocked = RelayLocked });
}
