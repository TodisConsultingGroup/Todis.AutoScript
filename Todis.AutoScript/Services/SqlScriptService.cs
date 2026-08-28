using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Todis.AutoScript.Models;
using Todis.AutoScript.Resources;

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
        bool useSingleTransaction,
        IProgress<(int Completed, string Message)> progress,
        CancellationToken token)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(token);
        SqlTransaction? sharedTransaction = useSingleTransaction
            ? (SqlTransaction)await connection.BeginTransactionAsync(token)
            : null;
        ScriptRunItem? currentItem = null;

        try
        {
            for (var index = 0; index < scripts.Count; index++)
            {
                token.ThrowIfCancellationRequested();
                currentItem = scripts[index];
                currentItem.Status = Strings.Running;
                progress.Report((index, Strings.RunningScript(currentItem.FileName)));
                var ownsTransaction = sharedTransaction is null;
                var transaction = sharedTransaction ??
                    (SqlTransaction)await connection.BeginTransactionAsync(token);

                try
                {
                    await ExecuteScriptAsync(connection, transaction, currentItem, token);
                    if (ownsTransaction)
                    {
                        await transaction.CommitAsync(token);
                        currentItem.Details = Strings.ExecutedCommitted;
                    }
                    else currentItem.Details = Strings.ExecutedPendingTransaction;

                    currentItem.Status = Strings.Done;
                    progress.Report((index + 1, Strings.ExecutedScript(currentItem.FileName)));
                }
                catch
                {
                    if (ownsTransaction)
                    {
                        try { await transaction.RollbackAsync(CancellationToken.None); }
                        catch { /* Zachowujemy pierwotny błąd. */ }
                    }
                    currentItem.Status = Strings.Error;
                    throw;
                }
                finally
                {
                    if (ownsTransaction) await transaction.DisposeAsync();
                }
            }

            if (sharedTransaction is not null)
            {
                await sharedTransaction.CommitAsync(token);
                foreach (var item in scripts) item.Details = Strings.ExecutedCommitted;
            }
        }
        catch
        {
            if (sharedTransaction is not null)
            {
                try { await sharedTransaction.RollbackAsync(CancellationToken.None); }
                catch { /* Pierwotny błąd wykonania jest ważniejszy niż błąd rollbacku. */ }
                foreach (var item in scripts.Where(item => item.Status == Strings.Done))
                {
                    item.Status = Strings.RolledBack;
                    item.Details = Strings.WholeTransactionRolledBack;
                }
            }
            if (currentItem is not null) currentItem.Status = Strings.Error;
            throw;
        }
        finally
        {
            if (sharedTransaction is not null) await sharedTransaction.DisposeAsync();
        }
    }

    private static async Task ExecuteScriptAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        ScriptRunItem item,
        CancellationToken token)
    {
        var targetVersion = GetTargetVersion(item.FileName);
        var currentVersion = await ReadDatabaseVersionAsync(connection, transaction, token);
        if (currentVersion != targetVersion - 1)
            throw new ScriptExecutionException(item.FileName, 1,
                Strings.InvalidDatabaseVersion(targetVersion - 1, currentVersion));

        var sql = await File.ReadAllTextAsync(item.FullPath, token);
        foreach (var batch in SplitBatches(sql))
        {
            await using var command = new SqlCommand(batch.Sql, connection, transaction) { CommandTimeout = 0 };
            try { await command.ExecuteNonQueryAsync(token); }
            catch (SqlException ex)
            {
                var line = batch.StartLine + Math.Max(0, ex.LineNumber - 1);
                throw new ScriptExecutionException(item.FileName, line, ex.Message, ex);
            }
        }

        var versionAfterScript = await ReadDatabaseVersionAsync(connection, transaction, token);
        if (versionAfterScript != targetVersion)
            throw new ScriptExecutionException(item.FileName, 1,
                Strings.TargetVersionNotSet(targetVersion, versionAfterScript));
    }

    private static int GetTargetVersion(string fileName)
    {
        var match = TargetVersionRegex().Match(fileName);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out var version) || version < 1)
            throw new ScriptExecutionException(fileName, 1,
                Strings.InvalidFileName);
        return version;
    }

    private static async Task<int> ReadDatabaseVersionAsync(
        SqlConnection connection, SqlTransaction transaction, CancellationToken token)
    {
        const string sql = "SELECT CASE WHEN COUNT(*) = 1 THEN MAX(VersionID) ELSE NULL END FROM dbo.tSysDBVersion;";
        await using var command = new SqlCommand(sql, connection, transaction);
        var value = await command.ExecuteScalarAsync(token);
        if (value is null or DBNull)
            throw new InvalidOperationException(Strings.InvalidVersionTable);
        return Convert.ToInt32(value);
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

    [GeneratedRegex(@"^(\d+)[_-]")]
    private static partial Regex TargetVersionRegex();
}

public sealed record SqlBatch(string Sql, int StartLine);

public sealed class ScriptExecutionException(string script, int line, string message, Exception? inner = null)
    : Exception(Strings.ScriptException(script, line, message), inner)
{
    public string Script { get; } = script;
    public int Line { get; } = line;
}
