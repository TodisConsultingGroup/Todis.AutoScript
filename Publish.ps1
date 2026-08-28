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
$stagingPath = Join-Path $OutputRoot ".$packageName-staging"
$zipPath = Join-Path $OutputRoot "$packageName.zip"

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
}

dotnet publish $projectPath `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --output $stagingPath `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0) {
    throw "Publikacja nie powiodła się (kod: $LASTEXITCODE)."
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -LiteralPath $stagingPath -Recurse -Force

Write-Host ""
Write-Host "Gotowa paczka: $zipPath" -ForegroundColor Green
Write-Host "Wersja: $version" -ForegroundColor Green
Write-Host "Przekaż użytkownikowi plik ZIP."
