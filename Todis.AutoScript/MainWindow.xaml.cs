using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Data.SqlClient;
using Microsoft.Win32;
using System.Windows.Threading;
using Todis.AutoScript.Models;
using Todis.AutoScript.Resources;
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
    private FileSystemWatcher? _scriptsWatcher;
    private readonly DispatcherTimer _refreshTimer;
    private bool _isRunning;
    private bool _refreshPending;
    private string _currentTheme = "Light";

    public MainWindow()
    {
        InitializeComponent();
        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _refreshTimer.Tick += (_, _) =>
        {
            _refreshTimer.Stop();
            if (_isRunning) { _refreshPending = true; return; }
            RefreshFolders();
        };
        ScriptsGrid.ItemsSource = _scripts;
        ScriptsGrid.AlternationCount = int.MaxValue;
        Loaded += async (_, _) => await LoadConfigAsync();
        Closed += (_, _) => _scriptsWatcher?.Dispose();
        Closing += (_, _) => SaveGridSettingsOnClose();
    }

    private async Task LoadConfigAsync()
    {
        _config = await _configService.LoadAsync();
        var projectScriptsRoot = Path.Combine(FindApplicationRoot(), "Scripts");
        var oldOutputScriptsRoot = Path.Combine(AppContext.BaseDirectory, "Scripts");
        if (string.IsNullOrWhiteSpace(_config.ScriptsRoot) ||
            (PathsEqual(_config.ScriptsRoot, oldOutputScriptsRoot) && !PathsEqual(projectScriptsRoot, oldOutputScriptsRoot)))
            _config.ScriptsRoot = projectScriptsRoot;
        Directory.CreateDirectory(_config.ScriptsRoot);
        ServerTextBox.Text = _config.Server;
        DatabaseTextBox.Text = _config.Database;
        AuthenticationComboBox.SelectedIndex = _config.UseWindowsAuthentication ? 0 : 1;
        UserNameTextBox.Text = _config.UserName;
        PasswordInput.Password = ConfigService.Unprotect(_config.ProtectedPassword);
        TrustCertificateCheckBox.IsChecked = _config.TrustServerCertificate;
        SingleTransactionCheckBox.IsChecked = _config.RunInSingleTransaction;
        ApplyTheme(_config.Theme);
        ApplyGridColumnSettings();
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
            TrustServerCertificate = TrustCertificateCheckBox.IsChecked == true,
            Theme = _currentTheme,
            GridColumns = ReadGridColumnSettings(),
            RunInSingleTransaction = SingleTransactionCheckBox.IsChecked == true
        };
    }

    private List<GridColumnSetting> ReadGridColumnSettings() => ScriptsGrid.Columns
        .Select(column => new GridColumnSetting
        {
            Value = column.Width.Value,
            UnitType = column.Width.UnitType.ToString()
        }).ToList();

    private void ApplyGridColumnSettings()
    {
        if (_config.GridColumns.Count != ScriptsGrid.Columns.Count) return;
        for (var i = 0; i < ScriptsGrid.Columns.Count; i++)
        {
            var setting = _config.GridColumns[i];
            if (setting.Value <= 0 || double.IsNaN(setting.Value) || double.IsInfinity(setting.Value)) continue;
            if (!Enum.TryParse<DataGridLengthUnitType>(setting.UnitType, out var unitType))
                unitType = DataGridLengthUnitType.Pixel;
            ScriptsGrid.Columns[i].Width = new DataGridLength(setting.Value, unitType);
        }
    }

    private void SaveGridSettingsOnClose()
    {
        if (_loading) return;
        try
        {
            _config = ReadForm();
            _configService.Save(_config);
        }
        catch { /* Zamknięcia aplikacji nie blokujemy błędem zapisu preferencji. */ }
    }

    private async void ToggleThemeClick(object sender, RoutedEventArgs e)
    {
        ApplyTheme(_currentTheme == "Dark" ? "Light" : "Dark");
        _config = ReadForm();
        await _configService.SaveAsync(_config);
    }

    private void ApplyTheme(string theme)
    {
        var dark = string.Equals(theme, "Dark", StringComparison.OrdinalIgnoreCase);
        _currentTheme = dark ? "Dark" : "Light";
        SetBrush("WindowBackgroundBrush", dark ? "#0F172A" : "#F3F4F6");
        SetBrush("SurfaceBrush", dark ? "#1E293B" : "#FFFFFF");
        SetBrush("ControlBackgroundBrush", dark ? "#334155" : "#FFFFFF");
        // Natywny popup ComboBox korzysta z jasnego tła systemowego, więc wymaga ciemnego tekstu.
        SetBrush("ComboBoxTextBrush", "#111827");
        SetBrush("TextBrush", dark ? "#F1F5F9" : "#111827");
        SetBrush("MutedTextBrush", dark ? "#94A3B8" : "#6B7280");
        SetBrush("BorderBrush", dark ? "#475569" : "#D1D5DB");
        SetBrush("SecondaryButtonBrush", dark ? "#334155" : "#E5E7EB");
        SetBrush("LogBackgroundBrush", dark ? "#020617" : "#111827");
        SetBrush("LogTextBrush", dark ? "#E2E8F0" : "#E5E7EB");
        ThemeToggleButton.Content = dark ? "\uE706" : "\uE708";
        ThemeToggleButton.ToolTip = dark ? Strings.EnableLightTheme : Strings.EnableDarkTheme;
    }

    private static void SetBrush(string key, string color) =>
        Application.Current.Resources[key] = new System.Windows.Media.SolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));

    private string BuildConnectionString()
    {
        _config = ReadForm();
        if (string.IsNullOrWhiteSpace(_config.Server) || string.IsNullOrWhiteSpace(_config.Database))
            throw new InvalidOperationException(Strings.EnterServerAndDatabase);
        if (!_config.UseWindowsAuthentication && (string.IsNullOrWhiteSpace(_config.UserName) || string.IsNullOrEmpty(PasswordInput.Password)))
            throw new InvalidOperationException(Strings.EnterSqlCredentials);
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
        AppendLog(Strings.SettingsSaved);
    }

    private async void TestConnectionClick(object sender, RoutedEventArgs e)
    {
        try
        {
            IsEnabled = false;
            AppendLog(Strings.TestingConnection);
            await _sqlService.TestConnectionAsync(BuildConnectionString(), CancellationToken.None);
            AppendLog(Strings.ConnectionWorks);
            MessageBox.Show(Strings.ConnectionWorksMessage, Strings.Success, MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { ShowError(Strings.ConnectionFailed, ex); }
        finally { IsEnabled = true; }
    }

    private void AuthenticationChanged(object sender, SelectionChangedEventArgs e) { if (!_loading) UpdateAuthenticationUi(); }
    private void UpdateAuthenticationUi() => SqlCredentialsPanel.Visibility = AuthenticationComboBox.SelectedIndex == 1 ? Visibility.Visible : Visibility.Collapsed;

    private void ChooseRootClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = Strings.ChooseScriptsFolder, InitialDirectory = ScriptsRootTextBox.Text };
        if (dialog.ShowDialog() == true) { ScriptsRootTextBox.Text = dialog.FolderName; RefreshFolders(); }
    }

    private void RefreshFoldersClick(object sender, RoutedEventArgs e) => RefreshFolders();
    private void RefreshFolders()
    {
        var previous = ScriptFolderComboBox.SelectedItem?.ToString() ?? _config.SelectedFolder;
        ScriptFolderComboBox.Items.Clear();
        var root = ScriptsRootTextBox.Text;
        ConfigureScriptsWatcher(root);
        if (Directory.Exists(root))
            foreach (var folder in Directory.GetDirectories(root).OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase))
                ScriptFolderComboBox.Items.Add(Path.GetFileName(folder));
        ScriptFolderComboBox.SelectedItem = previous;
        if (ScriptFolderComboBox.SelectedIndex < 0 && ScriptFolderComboBox.Items.Count > 0) ScriptFolderComboBox.SelectedIndex = 0;
        if (ScriptFolderComboBox.Items.Count == 0) { _scripts.Clear(); SummaryText.Text = Strings.NoScriptFolders; }
        else if (ScriptFolderComboBox.SelectedItem is string selectedFolder) LoadScripts(selectedFolder);
    }

    private void ConfigureScriptsWatcher(string root)
    {
        if (!Directory.Exists(root)) return;
        if (_scriptsWatcher is not null && PathsEqual(_scriptsWatcher.Path, root)) return;

        _scriptsWatcher?.Dispose();
        _scriptsWatcher = new FileSystemWatcher(root)
        {
            IncludeSubdirectories = true,
            Filter = "*",
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite,
            EnableRaisingEvents = true
        };
        _scriptsWatcher.Created += ScriptsChanged;
        _scriptsWatcher.Deleted += ScriptsChanged;
        _scriptsWatcher.Renamed += ScriptsChanged;
        _scriptsWatcher.Changed += ScriptsChanged;
    }

    private void ScriptsChanged(object sender, FileSystemEventArgs e)
    {
        var isSqlFile = string.Equals(Path.GetExtension(e.FullPath), ".sql", StringComparison.OrdinalIgnoreCase);
        var isDirectoryChange = string.IsNullOrEmpty(Path.GetExtension(e.FullPath));
        if (!isSqlFile && !isDirectoryChange) return;

        Dispatcher.BeginInvoke(() =>
        {
            _refreshTimer.Stop();
            _refreshTimer.Start();
        });
    }

    private void ScriptFolderChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ScriptFolderComboBox.SelectedItem is not string folder) return;
        LoadScripts(folder);
    }

    private void LoadScripts(string folder)
    {
        _scripts.Clear();
        var files = SqlScriptService.GetScriptFiles(Path.Combine(ScriptsRootTextBox.Text, folder));
        foreach (var file in files) _scripts.Add(new ScriptRunItem { FileName = Path.GetFileName(file), FullPath = file });
        SummaryText.Text = Strings.SetSummary(folder, _scripts.Count);
        RunProgress.Maximum = Math.Max(1, _scripts.Count); RunProgress.Value = 0;
    }

    private static bool PathsEqual(string first, string second) =>
        string.Equals(
            Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar),
            Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);

    private async void RunScriptsClick(object sender, RoutedEventArgs e)
        => await RunScriptsAsync(0);

    private async void ResumeScriptsClick(object sender, RoutedEventArgs e)
    {
        if (ScriptsGrid.SelectedItem is ScriptRunItem selected)
            await RunScriptsAsync(_scripts.IndexOf(selected));
    }

    private void ScriptsGridSelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateResumeButton();
    private void TransactionModeChanged(object sender, RoutedEventArgs e) => UpdateResumeButton();

    private void UpdateResumeButton()
    {
        if (!IsInitialized) return;
        ResumeButton.IsEnabled = !_isRunning &&
            SingleTransactionCheckBox.IsChecked != true &&
            ScriptsGrid.SelectedItem is ScriptRunItem;
    }

    private async Task RunScriptsAsync(int startIndex)
    {
        if (_scripts.Count == 0) { MessageBox.Show(Strings.NoSqlFiles, Strings.NoScriptsTitle, MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        var singleTransaction = SingleTransactionCheckBox.IsChecked == true;
        if (singleTransaction) startIndex = 0;
        var scriptsToRun = _scripts.Skip(startIndex).ToList();
        var transactionInfo = singleTransaction
            ? Strings.SingleTransactionInfo
            : Strings.SeparateTransactionsInfo;
        var answer = MessageBox.Show(
            Strings.RunConfirmation(scriptsToRun.Count, DatabaseTextBox.Text, scriptsToRun[0].FileName, transactionInfo),
            Strings.ConfirmExecution, MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes) return;
        try
        {
            RunButton.IsEnabled = false;
            ResumeButton.IsEnabled = false;
            _isRunning = true;
            StartRunLog();
            AppendLog(Strings.RunLogStart(ServerTextBox.Text.Trim(), DatabaseTextBox.Text.Trim(), ScriptFolderComboBox.SelectedItem, scriptsToRun[0].FileName));
            for (var i = 0; i < _scripts.Count; i++)
            {
                _scripts[i].Status = i < startIndex ? Strings.Skipped : Strings.Pending;
                _scripts[i].Details = i < startIndex ? Strings.SkippedOnResume : string.Empty;
            }
            await _configService.SaveAsync(ReadForm());
            RunProgress.Maximum = scriptsToRun.Count;
            RunProgress.Value = 0;
            var progress = new Progress<(int Completed, string Message)>(p => { RunProgress.Value = p.Completed; AppendLog(p.Message); });
            await _sqlService.ExecuteAsync(BuildConnectionString(), scriptsToRun, singleTransaction, progress, CancellationToken.None);
            AppendLog(Strings.AllScriptsSucceeded);
            AppendLog(Strings.LogSaved(_currentLogPath));
            MessageBox.Show(Strings.AllScriptsSucceeded, Strings.Done, MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (ScriptExecutionException ex)
        {
            var item = _scripts.FirstOrDefault(x => x.FileName == ex.Script);
            if (item is not null) item.Details = Strings.LineError(ex.Line, ex.InnerException?.Message ?? ex.Message);
            ShowError(Strings.ExecutionStopped, ex);
        }
        catch (Exception ex) { ShowError(Strings.ExecutionStopped, ex); }
        finally
        {
            _isRunning = false;
            RunButton.IsEnabled = true;
            UpdateResumeButton();
            if (_refreshPending) { _refreshPending = false; RefreshFolders(); }
        }
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
        var directory = Path.Combine(FindApplicationRoot(), "Logs");
        Directory.CreateDirectory(directory);
        _currentLogPath = Path.Combine(directory, $"run_{DateTime.Now:yyyyMMdd_HHmmss}.log");
    }

    private static string FindApplicationRoot()
    {
        // Podczas pracy z Visual Studio zapisuje logi w katalogu projektu.
        // Po publikacji, gdy nie ma pliku .csproj, zapisuje je obok programu.
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Todis.AutoScript.csproj")))
                return directory.FullName;
            directory = directory.Parent;
        }
        return AppContext.BaseDirectory;
    }

    private void ShowError(string title, Exception ex)
    {
        AppendLog(Strings.ErrorLog(ex.Message));
        MessageBox.Show(ex.Message, title, MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
