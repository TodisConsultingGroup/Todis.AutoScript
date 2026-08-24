param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$projectPath = Join-Path $repositoryRoot 'Todis.AutoScript\Todis.AutoScript.csproj'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'artifacts\Todis.AutoScript-win-x64'
}

dotnet publish $projectPath `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --output $OutputPath `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0) {
    throw "Publikacja nie powiodła się (kod: $LASTEXITCODE)."
}

Write-Host ""
Write-Host "Gotowa aplikacja: $OutputPath" -ForegroundColor Green
Write-Host "Przekaż użytkownikowi cały ten katalog, nie tylko plik EXE."
