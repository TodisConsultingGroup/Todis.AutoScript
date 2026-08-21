using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Data.SqlClient;
using Microsoft.Win32;
using Todis.AutoScript.Models;
using Todis.AutoScript.Services;

namespace Todis.AutoScript;

public partial class MainWindow : Window
{
    private readonly ConfigService _configService = new();
    private readonly SqlScriptService _sqlService = new();
    private readonly ObservableCollection<ScriptRunItem> _scripts = [];
    private AppConfig _config = new();
    private bool _loading = true;
    private string? _currentLogPath;

    public MainWindow()
    {
        InitializeComponent();
        ScriptsGrid.ItemsSource = _scripts;
        ScriptsGrid.AlternationCount = int.MaxValue;
        Loaded += async (_, _) => await LoadConfigAsync();
    }

    private async Task LoadConfigAsync()
    {
        _config = await _configService.LoadAsync();
        if (string.IsNullOrWhiteSpace(_config.ScriptsRoot))
            _config.ScriptsRoot = Path.Combine(AppContext.BaseDirectory, "Scripts");
        Directory.CreateDirectory(_config.ScriptsRoot);
        ServerTextBox.Text = _config.Server;
        DatabaseTextBox.Text = _config.Database;
        AuthenticationComboBox.SelectedIndex = _config.UseWindowsAuthentication ? 0 : 1;
        UserNameTextBox.Text = _config.UserName;
        PasswordInput.Password = ConfigService.Unprotect(_config.ProtectedPassword);
        TrustCertificateCheckBox.IsChecked = _config.TrustServerCertificate;
        ScriptsRootTextBox.Text = _config.ScriptsRoot;
        _loading = false;
        UpdateAuthenticationUi();
        RefreshFolders();
    }

    private AppConfig ReadForm()
    {
        var windowsAuth = AuthenticationComboBox.SelectedIndex != 1;
        return new AppConfig
        {
            Server = ServerTextBox.Text.Trim(), Database = DatabaseTextBox.Text.Trim(),
            UseWindowsAuthentication = windowsAuth, UserName = UserNameTextBox.Text.Trim(),
            ProtectedPassword = windowsAuth ? string.Empty : ConfigService.Protect(PasswordInput.Password),
            ScriptsRoot = ScriptsRootTextBox.Text, SelectedFolder = ScriptFolderComboBox.SelectedItem?.ToString() ?? string.Empty,
            TrustServerCertificate = TrustCertificateCheckBox.IsChecked == true
        };
    }

    private string BuildConnectionString()
    {
        _config = ReadForm();
        if (string.IsNullOrWhiteSpace(_config.Server) || string.IsNullOrWhiteSpace(_config.Database))
            throw new InvalidOperationException("Podaj serwer i nazwę bazy danych.");
        if (!_config.UseWindowsAuthentication && (string.IsNullOrWhiteSpace(_config.UserName) || string.IsNullOrEmpty(PasswordInput.Password)))
            throw new InvalidOperationException("Dla uwierzytelniania SQL podaj login i hasło.");
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = _config.Server, InitialCatalog = _config.Database,
            IntegratedSecurity = _config.UseWindowsAuthentication,
            TrustServerCertificate = _config.TrustServerCertificate,
            Encrypt = true, ConnectTimeout = 15, ApplicationName = "Todis AutoScript"
        };
        if (!_config.UseWindowsAuthentication) { builder.UserID = _config.UserName; builder.Password = PasswordInput.Password; }
        return builder.ConnectionString;
    }

    private async void SaveSettingsClick(object sender, RoutedEventArgs e)
    {
        _config = ReadForm();
        await _configService.SaveAsync(_config);
        AppendLog("Ustawienia zapisane lokalnie.");
    }

    private async void TestConnectionClick(object sender, RoutedEventArgs e)
    {
        try
        {
            IsEnabled = false;
            AppendLog("Testowanie połączenia…");
            await _sqlService.TestConnectionAsync(BuildConnectionString(), CancellationToken.None);
            AppendLog("Połączenie działa poprawnie.");
            MessageBox.Show("Połączenie z bazą działa poprawnie.", "Sukces", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { ShowError("Nie udało się połączyć", ex); }
        finally { IsEnabled = true; }
    }

    private void AuthenticationChanged(object sender, SelectionChangedEventArgs e) { if (!_loading) UpdateAuthenticationUi(); }
    private void UpdateAuthenticationUi() => SqlCredentialsPanel.Visibility = AuthenticationComboBox.SelectedIndex == 1 ? Visibility.Visible : Visibility.Collapsed;

    private void ChooseRootClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Wybierz folder zawierający zestawy skryptów", InitialDirectory = ScriptsRootTextBox.Text };
        if (dialog.ShowDialog() == true) { ScriptsRootTextBox.Text = dialog.FolderName; RefreshFolders(); }
    }

    private void RefreshFoldersClick(object sender, RoutedEventArgs e) => RefreshFolders();
    private void RefreshFolders()
    {
        var previous = _config.SelectedFolder;
        ScriptFolderComboBox.Items.Clear();
        var root = ScriptsRootTextBox.Text;
        if (Directory.Exists(root))
            foreach (var folder in Directory.GetDirectories(root).OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase))
                ScriptFolderComboBox.Items.Add(Path.GetFileName(folder));
        ScriptFolderComboBox.SelectedItem = previous;
        if (ScriptFolderComboBox.SelectedIndex < 0 && ScriptFolderComboBox.Items.Count > 0) ScriptFolderComboBox.SelectedIndex = 0;
        if (ScriptFolderComboBox.Items.Count == 0) { _scripts.Clear(); SummaryText.Text = "Brak podfolderów ze skryptami."; }
    }

    private void ScriptFolderChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ScriptFolderComboBox.SelectedItem is not string folder) return;
        _scripts.Clear();
        var files = SqlScriptService.GetScriptFiles(Path.Combine(ScriptsRootTextBox.Text, folder));
        foreach (var file in files) _scripts.Add(new ScriptRunItem { FileName = Path.GetFileName(file), FullPath = file });
        SummaryText.Text = $"{folder} — {_scripts.Count} skryptów (kolejność alfabetyczna)";
        RunProgress.Maximum = Math.Max(1, _scripts.Count); RunProgress.Value = 0;
    }

    private async void RunScriptsClick(object sender, RoutedEventArgs e)
    {
        if (_scripts.Count == 0) { MessageBox.Show("Wybrany folder nie zawiera plików .sql.", "Brak skryptów", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        var answer = MessageBox.Show($"Uruchomić {_scripts.Count} skryptów na bazie „{DatabaseTextBox.Text}” w podanej kolejności?\n\nProces zatrzyma się na pierwszym błędzie.", "Potwierdź uruchomienie", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes) return;
        try
        {
            RunButton.IsEnabled = false;
            StartRunLog();
            AppendLog($"START | Serwer: {ServerTextBox.Text.Trim()} | Baza: {DatabaseTextBox.Text.Trim()} | Zestaw: {ScriptFolderComboBox.SelectedItem}");
            foreach (var item in _scripts) { item.Status = "Oczekuje"; item.Details = string.Empty; }
            await _configService.SaveAsync(ReadForm());
            var progress = new Progress<(int Completed, string Message)>(p => { RunProgress.Value = p.Completed; AppendLog(p.Message); });
            await _sqlService.ExecuteAsync(BuildConnectionString(), _scripts.ToList(), progress, CancellationToken.None);
            AppendLog("Wszystkie skrypty wykonano poprawnie.");
            AppendLog($"Log zapisano w: {_currentLogPath}");
            MessageBox.Show("Wszystkie skrypty wykonano poprawnie.", "Gotowe", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (ScriptExecutionException ex)
        {
            var item = _scripts.FirstOrDefault(x => x.FileName == ex.Script);
            if (item is not null) item.Details = $"Linia {ex.Line}: {ex.InnerException?.Message ?? ex.Message}";
            ShowError("Wykonywanie zatrzymane", ex);
        }
        catch (Exception ex) { ShowError("Wykonywanie zatrzymane", ex); }
        finally { RunButton.IsEnabled = true; }
    }

    private void AppendLog(string text)
    {
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {text}{Environment.NewLine}";
        LogTextBox.AppendText(line);
        LogTextBox.ScrollToEnd();
        if (_currentLogPath is not null)
        {
            try { File.AppendAllText(_currentLogPath, line); }
            catch { /* Problem z logiem nie może zatrzymać wykonywania SQL. */ }
        }
    }

    private void StartRunLog()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Todis.AutoScript", "Logs");
        Directory.CreateDirectory(directory);
        _currentLogPath = Path.Combine(directory, $"run_{DateTime.Now:yyyyMMdd_HHmmss}.log");
    }

    private void ShowError(string title, Exception ex)
    {
        AppendLog($"BŁĄD: {ex.Message}");
        MessageBox.Show(ex.Message, title, MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
