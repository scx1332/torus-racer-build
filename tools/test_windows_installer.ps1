#requires -Version 7.2
# Destructive install/uninstall smoke test: only a disposable GitHub-hosted Windows runner.
# Every child process is bounded here rather than by the workflow alone: a step
# timeout does not reliably kill a process tree that still holds the output pipes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Installer smoke tests require a GitHub-hosted Windows Actions runner.'
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$msiPath = (Resolve-Path -LiteralPath (Join-Path $repositoryRoot 'build/installer/TorusRacer.msi')).Path
$installDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TorusRacer'
$shortcutDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Torus Racer'
$executablePath = Join-Path $installDirectory 'TorusRacer.exe'
$packPath = Join-Path $installDirectory 'TorusRacer.pck'
$shortcutPath = Join-Path $shortcutDirectory 'Torus Racer.lnk'

# Never replace an existing installation, shortcut directory, or installer registration.
foreach ($existingPath in @($installDirectory, $shortcutDirectory, 'HKCU:\Software\TorusRacer\Installer')) {
    if (Test-Path -LiteralPath $existingPath) {
        throw "Refusing to modify pre-existing installer state: $existingPath"
    }
}

$logDirectory = Join-Path $repositoryRoot 'build/installer-test'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$installLog = Join-Path $logDirectory 'install.log'
$gameLog = Join-Path $logDirectory 'game.log'
$uninstallLog = Join-Path $logDirectory 'uninstall.log'
$msiexecPath = Join-Path ([Environment]::GetFolderPath('System')) 'msiexec.exe'

function Start-BoundedProcess {
    param(
        [string] $FilePath,
        [string] $ArgumentList,
        [string] $WorkingDirectory,
        [int] $TimeoutSeconds,
        [string] $Description
    )

    $parameters = @{ FilePath = $FilePath; ArgumentList = $ArgumentList; PassThru = $true }
    if ($WorkingDirectory) {
        $parameters['WorkingDirectory'] = $WorkingDirectory
    }
    # Deliberately not -Wait: that also waits for descendants, and the msiexec
    # service lingers for minutes after an install, which hangs the whole step.
    # WaitForExit waits for this process only and takes a timeout.
    $process = Start-Process @parameters
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill($true)
        }
        catch {
            Write-Warning "Could not kill the timed-out process: $($_.Exception.Message)"
        }
        throw "$Description did not finish within $TimeoutSeconds seconds."
    }
    return $process.ExitCode
}

function Invoke-TestMsi {
    param(
        [ValidateSet('/i', '/x')][string] $Operation,
        [string] $LogPath
    )

    # ArgumentList is one explicitly quoted Windows command line, including paths with spaces.
    $arguments = '{0} "{1}" /qn /norestart /L*v "{2}"' -f $Operation, $msiPath, $LogPath
    $exitCode = Start-BoundedProcess -FilePath $msiexecPath -ArgumentList $arguments `
        -TimeoutSeconds 300 -Description "msiexec $Operation"
    if ($exitCode -notin @(0, 3010)) {
        throw "msiexec $Operation failed with exit code $exitCode. See $LogPath"
    }
    Write-Host "msiexec $Operation completed with exit code $exitCode."
}

$installationAttempted = $false
$failure = $null
try {
    $installationAttempted = $true
    Invoke-TestMsi -Operation '/i' -LogPath $installLog
    foreach ($installedFile in @($executablePath, $packPath, $shortcutPath)) {
        if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf)) {
            throw "The MSI did not install its expected file: $installedFile"
        }
    }

    # Launch from the installed directory, so the repository cannot supply missing resources.
    # The real game may read its normal user data; this test creates no fake lap records.
    $gameArguments = '--headless --log-file "{0}" --quit-after 120' -f $gameLog
    $gameExitCode = Start-BoundedProcess -FilePath $executablePath -ArgumentList $gameArguments `
        -WorkingDirectory $installDirectory -TimeoutSeconds 180 -Description 'The installed game'
    if ($gameExitCode -ne 0) {
        throw "The installed game exited with code $gameExitCode. See $gameLog"
    }
    if (-not (Test-Path -LiteralPath $gameLog -PathType Leaf)) {
        throw "The installed game did not produce its requested log: $gameLog"
    }
    $gameErrors = @(Select-String -LiteralPath $gameLog -Pattern '^\s*(?:SCRIPT ERROR|ERROR):')
    if ($gameErrors.Count -gt 0) {
        throw "The installed game reported errors:`n$($gameErrors.Line -join "`n")"
    }
    Write-Host 'Installed EXE, PCK, Start Menu shortcut, and headless game launch passed.'
}
catch {
    $failure = $_
}
finally {
    if ($installationAttempted) {
        try {
            # Uninstall only this exact MSI; never recursively delete install or user-data folders.
            Invoke-TestMsi -Operation '/x' -LogPath $uninstallLog
            $leftovers = @(@($installDirectory, $shortcutDirectory) | Where-Object {
                Test-Path -LiteralPath $_
            })
            if ($leftovers.Count -gt 0) {
                throw "Uninstall left game or shortcut files behind: $($leftovers -join ', ')"
            }
            Write-Host 'MSI uninstall removed the game and Start Menu shortcut.'
        }
        catch {
            if ($null -eq $failure) {
                $failure = $_
            }
            else {
                Write-Warning "Installer cleanup also failed: $($_.Exception.Message)"
            }
        }
    }
}

if ($null -ne $failure) {
    throw $failure
}
Write-Host "WINDOWS INSTALLER SMOKE PASS. Logs: $logDirectory"
