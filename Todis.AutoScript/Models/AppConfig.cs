namespace Todis.AutoScript.Models;

public sealed class AppConfig
{
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public bool UseWindowsAuthentication { get; set; } = true;
    public string UserName { get; set; } = string.Empty;
    public string ProtectedPassword { get; set; } = string.Empty;
    public string ScriptsRoot { get; set; } = string.Empty;
    public string SelectedFolder { get; set; } = string.Empty;
    public bool TrustServerCertificate { get; set; } = true;
    public string Theme { get; set; } = "Light";
    public List<GridColumnSetting> GridColumns { get; set; } = [];
}

public sealed class GridColumnSetting
{
    public double Value { get; set; }
    public string UnitType { get; set; } = "Pixel";
}
