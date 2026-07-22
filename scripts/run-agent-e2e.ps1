param(
    [switch]$KeepRunning,
    [switch]$NoBuild,
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 240,
    [ValidateRange(1024, 65535)]
    [int]$BackendPort = 18080,
    [ValidateRange(1024, 65535)]
    [int]$AgentServicePort = 18090
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $repoRoot "deploy\docker-compose.agent-e2e.yml"
$composeProject = "fitloop-agent-e2e"
$baseUrl = "http://127.0.0.1:$BackendPort"
$stackTouched = $false
$previousBackendPort = $env:FITLOOP_AGENT_E2E_BACKEND_PORT
$previousServicePort = $env:FITLOOP_AGENT_E2E_SERVICE_PORT

function Invoke-Compose([string[]]$Arguments, [switch]$AllowFailure) {
    & docker compose --project-name $composeProject --file $composeFile @Arguments
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE"
    }
}

function Invoke-FitLoopApi(
    [string]$Method,
    [string]$Path,
    [string]$Token = "",
    [object]$Body = $null
) {
    $request = @{
        Method = $Method
        Uri = "$baseUrl$Path"
        TimeoutSec = 20
        ErrorAction = "Stop"
    }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $request.Headers = @{ Authorization = "Bearer $Token" }
    }
    if ($null -ne $Body) {
        $request.ContentType = "application/json"
        $request.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    Invoke-RestMethod @request
}

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-ToolCalls([object]$Audit, [string[]]$ExpectedNames) {
    $actualNames = @($Audit.data.toolCalls | ForEach-Object { $_.toolName })
    foreach ($name in $ExpectedNames) {
        if ($actualNames -notcontains $name) {
            throw "Agent audit did not contain required tool '$name'. Actual: $($actualNames -join ', ')"
        }
    }
    $failed = @($Audit.data.toolCalls | Where-Object { -not $_.succeeded })
    if ($failed.Count -ne 0) {
        throw "Agent audit contains $($failed.Count) failed tool call(s)."
    }
}

function Wait-AgentRun([string]$RunId, [string]$Token) {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $response = Invoke-FitLoopApi -Method GET -Path "/api/v1/agent/runs/$RunId" -Token $Token
        $status = [string]$response.data.status
        if ($status -in @("FAILED_RETRYABLE", "FAILED_FINAL")) {
            throw "Agent run $RunId failed with status $status`: $($response.data.errorMessage)"
        }
        if ($status -in @("WAITING_APPROVAL", "SUCCEEDED")) {
            return $response.data
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Agent run $RunId did not reach a terminal or approval state within $TimeoutSeconds seconds."
}

function Restore-Environment {
    $env:FITLOOP_AGENT_E2E_BACKEND_PORT = $previousBackendPort
    $env:FITLOOP_AGENT_E2E_SERVICE_PORT = $previousServicePort
}

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI was not found. Install or start Docker Desktop before running this script."
    }
    docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop is not running or the current user cannot access the Docker engine."
    }

    $env:FITLOOP_AGENT_E2E_BACKEND_PORT = $BackendPort.ToString()
    $env:FITLOOP_AGENT_E2E_SERVICE_PORT = $AgentServicePort.ToString()

    Write-Host "[1/6] Starting isolated MySQL, Redis, Spring, model stub, and Agent worker"
    $stackTouched = $true
    $upArguments = @("up", "--detach", "--wait", "--wait-timeout", $TimeoutSeconds.ToString())
    if (-not $NoBuild) { $upArguments += "--build" }
    Invoke-Compose $upArguments

    Write-Host "[2/6] Logging in isolated user and administrator fixtures"
    $userLogin = Invoke-FitLoopApi -Method POST -Path "/api/v1/auth/login" -Body @{
        account = "agent.user@fitloop.local"
        password = "AgentUserDemo!2026"
        loginType = "password"
    }
    $adminLogin = Invoke-FitLoopApi -Method POST -Path "/api/v1/auth/login" -Body @{
        account = "agent.admin@fitloop.local"
        password = "AgentAdminDemo!2026"
        loginType = "password"
    }
    Assert-Equal $userLogin.role "USER" "Demo user role is incorrect."
    Assert-Equal $adminLogin.role "ADMIN" "Demo administrator role is incorrect."

    Write-Host "[3/6] Running coach workflow through Redis Stream and Agents SDK"
    $coachCreated = Invoke-FitLoopApi -Method POST -Path "/api/v1/agent/coach/runs" `
        -Token $userLogin.token -Body @{
            objective = "Build a safe two-session running plan from my current FitLoop evidence."
        }
    $coachRun = Wait-AgentRun -RunId $coachCreated.data.runId -Token $userLogin.token
    Assert-Equal $coachRun.status "WAITING_APPROVAL" "Coach run did not stop for user approval."
    if (@($coachRun.proposals).Count -ne 1) { throw "Coach run must create exactly one proposal." }
    $coachProposal = $coachRun.proposals[0]
    Assert-Equal $coachProposal.actionType "CREATE_TRAINING_PLAN" "Coach proposal action is incorrect."
    Assert-Equal $coachProposal.requiresAdmin $false "Coach proposal must require its user, not an administrator."
    $coachAudit = Invoke-FitLoopApi -Method GET `
        -Path "/api/v1/admin/agent/runs/$($coachRun.runId)/audit" -Token $adminLogin.token
    Assert-ToolCalls $coachAudit @(
        "get_user_goals",
        "get_recent_workouts",
        "get_health_trends",
        "get_goal_completion",
        "calculate_training_load"
    )

    Write-Host "[4/6] Confirming the coach proposal as the owning user"
    $coachConfirmed = Invoke-FitLoopApi -Method POST `
        -Path "/api/v1/agent/actions/$($coachProposal.proposalId)/confirm" -Token $userLogin.token
    Assert-Equal $coachConfirmed.data.status "CONFIRMED" "Coach proposal was not confirmed."
    if ($null -eq $coachConfirmed.data.affectedResourceId) {
        throw "Coach confirmation did not create a training plan."
    }

    Write-Host "[5/6] Running appeal-review workflow and enforcing administrator approval"
    $pendingAppeals = Invoke-FitLoopApi -Method GET `
        -Path "/api/v1/admin/appeals?status=pending&page=0&size=20" -Token $adminLogin.token
    $appeal = @($pendingAppeals.data.items | Where-Object {
        $_.reason -eq "A short tunnel section caused one isolated GPS speed spike."
    }) | Select-Object -First 1
    if ($null -eq $appeal) { throw "The isolated pending appeal fixture was not found." }

    $appealCreated = Invoke-FitLoopApi -Method POST `
        -Path "/api/v1/admin/appeals/$($appeal.appealId)/agent-review" -Token $adminLogin.token
    $appealRun = Wait-AgentRun -RunId $appealCreated.data.runId -Token $adminLogin.token
    Assert-Equal $appealRun.status "WAITING_APPROVAL" "Appeal run did not stop for administrator approval."
    if (@($appealRun.proposals).Count -ne 1) { throw "Appeal run must create exactly one proposal." }
    $appealProposal = $appealRun.proposals[0]
    Assert-Equal $appealProposal.actionType "REVIEW_APPEAL" "Appeal proposal action is incorrect."
    Assert-Equal $appealProposal.requiresAdmin $true "Appeal proposal must require an administrator."
    $appealAudit = Invoke-FitLoopApi -Method GET `
        -Path "/api/v1/admin/agent/runs/$($appealRun.runId)/audit" -Token $adminLogin.token
    Assert-ToolCalls $appealAudit @("get_appeal_evidence", "get_anomaly_rules")

    Write-Host "[6/6] Confirming the appeal proposal and verifying the domain change"
    $appealConfirmed = Invoke-FitLoopApi -Method POST `
        -Path "/api/v1/agent/actions/$($appealProposal.proposalId)/confirm" -Token $adminLogin.token
    Assert-Equal $appealConfirmed.data.status "CONFIRMED" "Appeal proposal was not confirmed."
    Assert-Equal $appealConfirmed.data.affectedResourceId $appeal.appealId `
        "Appeal confirmation changed an unexpected resource."
    $approvedAppeals = Invoke-FitLoopApi -Method GET `
        -Path "/api/v1/admin/appeals?status=approved&page=0&size=20" -Token $adminLogin.token
    if (@($approvedAppeals.data.items | Where-Object { $_.appealId -eq $appeal.appealId }).Count -ne 1) {
        throw "The confirmed Agent decision did not approve the seeded appeal."
    }

    [ordered]@{
        status = "SUCCESS"
        modelProvider = "deterministic-openai-compatible-stub"
        coachRunId = $coachRun.runId
        coachToolCalls = @($coachAudit.data.toolCalls).Count
        trainingPlanId = $coachConfirmed.data.affectedResourceId
        appealRunId = $appealRun.runId
        appealToolCalls = @($appealAudit.data.toolCalls).Count
        approvedAppealId = $appeal.appealId
    } | ConvertTo-Json -Depth 4
    Write-Host "agent-container-e2e=SUCCESS"
} catch {
    if ($stackTouched) {
        Write-Warning "Agent E2E failed. Printing bounded service logs before cleanup."
        Invoke-Compose @("logs", "--no-color", "--tail", "200", "backend", "agent-service", "model-stub") -AllowFailure
    }
    throw
} finally {
    if ($stackTouched -and -not $KeepRunning) {
        Write-Host "Cleaning isolated Agent E2E containers, network, and volumes"
        Invoke-Compose @("down", "--volumes", "--remove-orphans") -AllowFailure
    } elseif ($stackTouched) {
        Write-Host "Agent E2E stack kept running. Stop it with:"
        Write-Host "docker compose --project-name $composeProject --file `"$composeFile`" down --volumes --remove-orphans"
    }
    Restore-Environment
}
