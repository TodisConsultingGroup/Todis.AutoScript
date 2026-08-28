using System.ComponentModel;
using System.Runtime.CompilerServices;
using Todis.AutoScript.Resources;

namespace Todis.AutoScript.Models;

public sealed class ScriptRunItem : INotifyPropertyChanged
{
    private string _status = Strings.Pending;
    private string _details = string.Empty;

    public required string FileName { get; init; }
    public required string FullPath { get; init; }
    public string Status { get => _status; set { _status = value; OnPropertyChanged(); } }
    public string Details { get => _details; set { _details = value; OnPropertyChanged(); } }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
