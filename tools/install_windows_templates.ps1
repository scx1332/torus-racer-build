# Download the official archive, verify its pinned digest, then extract only x64 Windows.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string] $Sha256
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsWindows) { throw 'This template installer requires PowerShell 7 on Windows.' }
$ProgressPreference = 'SilentlyContinue'
$templateVersion = "$Version.stable"
$destination = Join-Path ([Environment]::GetFolderPath('ApplicationData')) "Godot/export_templates/$templateVersion"
$names = @('version.txt', 'windows_debug_x86_64.exe', 'windows_release_x86_64.exe')
foreach ($name in $names) {
    if (Test-Path -LiteralPath (Join-Path $destination $name)) {
        throw "Refusing to overwrite an existing export template: $name"
    }
}

$archive = [IO.Path]::GetTempFileName()
$zip = $null
try {
    $url = "https://github.com/godotengine/godot-builds/releases/download/$Version-stable/Godot_v$Version-stable_export_templates.tpz"
    Invoke-WebRequest -Uri $url -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Sha256) {
        throw 'Godot export template SHA256 mismatch; nothing will be installed.'
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    foreach ($name in $names) {
        if ($null -eq $zip.GetEntry("templates/$name")) {
            throw "The verified archive is missing templates/$name."
        }
    }
    $reader = [IO.StreamReader]::new($zip.GetEntry('templates/version.txt').Open())
    try {
        if ($reader.ReadToEnd().Trim() -ne $templateVersion) {
            throw 'Godot export template version mismatch.'
        }
    } finally {
        $reader.Dispose()
    }
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    foreach ($name in $names) {
        [IO.Compression.ZipFileExtensions]::ExtractToFile(
            $zip.GetEntry("templates/$name"), (Join-Path $destination $name), $false)
    }
    Write-Host "Installed verified Windows x64 templates: $destination"
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
    # Only remove the unique temporary archive owned by this invocation.
    [IO.File]::Delete($archive)
}
