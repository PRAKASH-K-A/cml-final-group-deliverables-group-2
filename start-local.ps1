param(
    [switch]$Build,
    [switch]$NoFrontend
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Stop-StaleBackendJavaProcesses {
    param([string]$WorkspaceRoot)

    Write-Host 'Checking for stale backend Java processes...' -ForegroundColor Yellow

    $escapedRoot = [Regex]::Escape($WorkspaceRoot)
    $patterns = @(
        "${escapedRoot}.*exchange-back-end.*quarkus-run\.jar",
        "${escapedRoot}.*broker-back-end.*quarkus-run\.jar",
        "${escapedRoot}.*exchange-back-end.*app\.jar",
        "${escapedRoot}.*broker-back-end.*app\.jar"
    )

    $stale = Get-CimInstance Win32_Process | Where-Object {
        if ($_.Name -ine 'java.exe' -or -not $_.CommandLine) { return $false }
        foreach ($pattern in $patterns) {
            if ($_.CommandLine -match $pattern) {
                return $true
            }
        }
        return $false
    }

    if (-not $stale) {
        Write-Host 'No stale backend Java processes found.' -ForegroundColor DarkGray
        return
    }

    foreach ($proc in $stale) {
        Write-Host ("Stopping stale process PID {0}" -f $proc.ProcessId) -ForegroundColor Yellow
        try {
            $result = Invoke-CimMethod -InputObject $proc -MethodName Terminate
            if ($result.ReturnValue -ne 0) {
                Write-Warning ("Terminate returned {0} for PID {1}" -f $result.ReturnValue, $proc.ProcessId)
            }
        } catch {
            Write-Warning ("Could not stop PID {0}: {1}" -f $proc.ProcessId, $_.Exception.Message)
        }
    }
}

function Start-ServiceWindow {
    param(
        [string]$Name,
        [string]$WorkingDir,
        [string]$Command
    )

    Write-Host "Starting $Name..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList @(
        '-NoExit',
        '-Command',
        "Set-Location '$WorkingDir'; $Command"
    ) | Out-Null
}

Write-Host 'Preparing FIX Trading Simulator local startup...' -ForegroundColor Green

Stop-StaleBackendJavaProcesses -WorkspaceRoot $root

if ($Build) {
    Write-Host 'Building exchange-back-end...' -ForegroundColor Yellow
    Push-Location (Join-Path $root 'exchange-back-end')
    mvn -q -DskipTests package
    Pop-Location

    Write-Host 'Building broker-back-end...' -ForegroundColor Yellow
    Push-Location (Join-Path $root 'broker-back-end')
    mvn -q -DskipTests package
    Pop-Location
}

$exchangeBackEndDir = Join-Path $root 'exchange-back-end'
$brokerBackEndDir = Join-Path $root 'broker-back-end'
$exchangeFrontEndDir = Join-Path $root 'exchange-front-end'
$brokerFrontEndDir = Join-Path $root 'broker-front-end'

# Start exchange first so FIX acceptor (9876) is available before broker initiator starts.
Start-ServiceWindow -Name 'Exchange Back-End (8090/9876)' -WorkingDir $exchangeBackEndDir -Command 'java -jar target\quarkus-app\quarkus-run.jar'
Start-Sleep -Seconds 4
Start-ServiceWindow -Name 'Broker Back-End (8080)' -WorkingDir $brokerBackEndDir -Command 'java -jar target\quarkus-app\quarkus-run.jar'

if (-not $NoFrontend) {
    Start-Sleep -Seconds 3
    Start-ServiceWindow -Name 'Exchange Front-End (4201)' -WorkingDir $exchangeFrontEndDir -Command 'npm start'
    Start-ServiceWindow -Name 'Broker Front-End (4200)' -WorkingDir $brokerFrontEndDir -Command 'npm start'
}

Write-Host ''
Write-Host 'Startup commands launched in separate windows.' -ForegroundColor Green
Write-Host 'Broker UI:   http://localhost:4200'
Write-Host 'Exchange UI: http://localhost:4201'
Write-Host 'Broker API:  http://localhost:8080/q/swagger-ui/'
Write-Host 'Exchange API:http://localhost:8090/q/swagger-ui/'
