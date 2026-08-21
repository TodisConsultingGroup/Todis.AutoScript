using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Todis.AutoScript.Models;

namespace Todis.AutoScript.Services;

public sealed partial class SqlScriptService
{
    public static IReadOnlyList<string> GetScriptFiles(string folder) =>
        Directory.Exists(folder)
            ? Directory.GetFiles(folder, "*.sql", SearchOption.TopDirectoryOnly)
                .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase).ToArray()
            : [];

    public async Task TestConnectionAsync(string connectionString, CancellationToken token)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(token);
    }

    public async Task ExecuteAsync(
        string connectionString,
        IReadOnlyList<ScriptRunItem> scripts,
        IProgress<(int Completed, string Message)> progress,
        CancellationToken token)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(token);

        for (var index = 0; index < scripts.Count; index++)
        {
            token.ThrowIfCancellationRequested();
            var item = scripts[index];
            item.Status = "Uruchamianie";
            progress.Report((index, $"Uruchamianie: {item.FileName}"));

            var sql = await File.ReadAllTextAsync(item.FullPath, token);
            var batches = SplitBatches(sql);
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(token);
            try
            {
                foreach (var batch in batches)
                {
                    await using var command = new SqlCommand(batch.Sql, connection, transaction) { CommandTimeout = 0 };
                    try { await command.ExecuteNonQueryAsync(token); }
                    catch (SqlException ex)
                    {
                        var line = batch.StartLine + Math.Max(0, ex.LineNumber - 1);
                        throw new ScriptExecutionException(item.FileName, line, ex.Message, ex);
                    }
                }
                await transaction.CommitAsync(token);
                item.Status = "Gotowe";
                item.Details = "Wykonano poprawnie";
                progress.Report((index + 1, $"Wykonano: {item.FileName}"));
            }
            catch
            {
                try { await transaction.RollbackAsync(CancellationToken.None); }
                catch { /* Pierwotny błąd wykonania jest ważniejszy niż błąd rollbacku. */ }
                item.Status = "Błąd";
                throw;
            }
        }
    }

    internal static IReadOnlyList<SqlBatch> SplitBatches(string sql)
    {
        var result = new List<SqlBatch>();
        var lines = sql.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var start = 1;
        var buffer = new List<string>();
        for (var i = 0; i < lines.Length; i++)
        {
            var match = GoLineRegex().Match(lines[i]);
            if (!match.Success) { buffer.Add(lines[i]); continue; }
            AddBatch(result, buffer, start, int.TryParse(match.Groups[1].Value, out var count) ? count : 1);
            buffer.Clear();
            start = i + 2;
        }
        AddBatch(result, buffer, start, 1);
        return result;
    }

    private static void AddBatch(List<SqlBatch> result, List<string> lines, int start, int repeat)
    {
        var text = string.Join(Environment.NewLine, lines);
        if (string.IsNullOrWhiteSpace(text)) return;
        for (var i = 0; i < repeat; i++) result.Add(new SqlBatch(text, start));
    }

    [GeneratedRegex(@"^\s*GO(?:\s+(\d+))?\s*(?:--.*)?$", RegexOptions.IgnoreCase)]
    private static partial Regex GoLineRegex();
}

public sealed record SqlBatch(string Sql, int StartLine);

public sealed class ScriptExecutionException(string script, int line, string message, Exception inner)
    : Exception($"{script}, linia {line}: {message}", inner)
{
    public string Script { get; } = script;
    public int Line { get; } = line;
}
