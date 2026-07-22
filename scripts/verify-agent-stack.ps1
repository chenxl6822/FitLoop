param(
    [switch]$Live,
    [string]$EnvFile = "",
    [string]$JavaHome = "",
    [string]$PythonExecutable = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"
$agentDir = Join-Path $repoRoot "agent-service"
$mavenSettings = Join-Path $repoRoot ".github\maven-settings.xml"

function Find-Jdk21([string]$RequestedHome) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedHome)) { $candidates.Add($RequestedHome) }
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) { $candidates.Add($env:JAVA_HOME) }

    $javaRoot = Join-Path $env:ProgramFiles "Java"
    if (Test-Path -LiteralPath $javaRoot) {
        Get-ChildItem -LiteralPath $javaRoot -Directory -Filter "jdk-21*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { $candidates.Add($_.FullName) }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        $java = Join-Path $candidate "bin\java.exe"
        if (-not (Test-Path -LiteralPath $java)) { continue }
        $version = (Get-Item -LiteralPath $java).VersionInfo.ProductVersion
        if ($version -match '^21\.') { return (Resolve-Path $candidate).Path }
    }
    throw "JDK 21 was not found. Pass -JavaHome with the JDK 21 installation directory."
}

function Find-Python312([string]$RequestedExecutable) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedExecutable)) {
        $candidates.Add($RequestedExecutable)
    }
    $candidates.Add((Join-Path $repoRoot ".tmp-agent-venv\Scripts\python.exe"))
    $candidates.Add((Join-Path $agentDir ".venv\Scripts\python.exe"))
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) { $candidates.Add($pythonCommand.Source) }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $version = (Get-Item -LiteralPath $candidate).VersionInfo.ProductVersion
        if ($version -match '^3\.1[2-9]') { return (Resolve-Path $candidate).Path }
    }
    throw "Python 3.12+ was not found. Pass -PythonExecutable with a compatible python.exe."
}

$jdk21 = Find-Jdk21 $JavaHome
$python = Find-Python312 $PythonExecutable
$previousJavaHome = $env:JAVA_HOME
$previousPath = $env:Path
$previousPythonPath = $env:PYTHONPATH
$env:JAVA_HOME = $jdk21
$env:Path = "$(Join-Path $jdk21 'bin');$env:Path"
$env:PYTHONPATH = Join-Path $agentDir "src"
$env:PYTHONUTF8 = "1"

try {
    Write-Host "[1/3] Verifying Spring Agent state, Redis Stream contract, and approval boundary"
    Push-Location $backendDir
    try {
        mvn --batch-mode --settings $mavenSettings `
            "-Dtest=AgentQueuePublisherTest,AgentGatewayServiceTest,AgentGatewayIntegrationTest,AgentStateMachineTest" `
            test
        if ($LASTEXITCODE -ne 0) { throw "Spring Agent verification failed." }
    } finally {
        Pop-Location
    }

    Write-Host "[2/3] Verifying Python Worker, provider adapter, guardrails, and demo contract"
    Push-Location $agentDir
    try {
        & $python -m compileall -q src tests
        if ($LASTEXITCODE -ne 0) { throw "Agent package compilation failed." }
        & $python -m pytest -q
        if ($LASTEXITCODE -ne 0) { throw "Agent pytest verification failed." }
    } finally {
        Pop-Location
    }

    if ($Live) {
        Write-Host "[3/3] Running real DeepSeek coach and appeal workflows"
        $resolvedEnvFile = if ([string]::IsNullOrWhiteSpace($EnvFile)) {
            Join-Path $repoRoot ".env"
        } else {
            $EnvFile
        }
        if (-not (Test-Path -LiteralPath $resolvedEnvFile)) {
            throw "Live demo environment file does not exist: $resolvedEnvFile"
        }
        & $python -m fitloop_agent.demo `
            --env-file $resolvedEnvFile `
            --mode all `
            --confirm-live-api
        if ($LASTEXITCODE -ne 0) { throw "Live DeepSeek Agent demo failed." }
    } else {
        Write-Host "[3/3] Live DeepSeek call skipped; pass -Live to include it."
    }

    Write-Host "agent-stack-verification=SUCCESS"
} finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:Path = $previousPath
    $env:PYTHONPATH = $previousPythonPath
}
