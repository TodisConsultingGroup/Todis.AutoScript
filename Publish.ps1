param(
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$projectPath = Join-Path $repositoryRoot 'Todis.AutoScript\Todis.AutoScript.csproj'
$projectXml = [xml](Get-Content -Raw -LiteralPath $projectPath)
$version = [string]($projectXml.Project.PropertyGroup.Version | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'Brak elementu <Version> w pliku projektu.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repositoryRoot 'artifacts'
}

$packageName = "Todis.AutoScript-v$version-win-x64"
$OutputPath = Join-Path $OutputRoot $packageName

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
Write-Host "Wersja: $version" -ForegroundColor Green
Write-Host "Przekaż użytkownikowi cały ten katalog, nie tylko plik EXE."
