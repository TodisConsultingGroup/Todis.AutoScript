using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Todis.AutoScript.Models;

namespace Todis.AutoScript.Services;

public sealed class ConfigService
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Todis.AutoScript.Config.v1");
    private readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Todis.AutoScript", "config.json");

    public async Task<AppConfig> LoadAsync()
    {
        if (!File.Exists(_path)) return new AppConfig();
        try
        {
            await using var stream = File.OpenRead(_path);
            return await JsonSerializer.DeserializeAsync<AppConfig>(stream) ?? new AppConfig();
        }
        catch (JsonException)
        {
            return new AppConfig();
        }
    }

    public async Task SaveAsync(AppConfig config)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        await using var stream = File.Create(_path);
        await JsonSerializer.SerializeAsync(stream, config, new JsonSerializerOptions { WriteIndented = true });
    }

    public void Save(AppConfig config)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        using var stream = File.Create(_path);
        JsonSerializer.Serialize(stream, config, new JsonSerializerOptions { WriteIndented = true });
    }

    public static string Protect(string value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), Entropy, DataProtectionScope.CurrentUser);
        return Convert.ToBase64String(bytes);
    }

    public static string Unprotect(string value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        try
        {
            var bytes = ProtectedData.Unprotect(Convert.FromBase64String(value), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch (CryptographicException) { return string.Empty; }
        catch (FormatException) { return string.Empty; }
    }
}
