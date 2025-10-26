<#
.SYNOPSIS
    Runs the complete end-to-end deployment for the local 'ora' environment.
.DESCRIPTION
    This script orchestrates the entire setup process:
    1. Starts Minikube
    2. Deploys the core platform (Postgres, Keycloak, NGINX, etc.)
    3. Deploys all backend microservices
    4. Deploys the frontend web application
#>

param(
    [string]$Namespace = "ora",
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\.." -ErrorAction Stop).Path
)

$sharedModule = Join-Path $PSScriptRoot "shared.psm1"
if (-not (Test-Path $sharedModule)) {
    throw "Shared functions module not found at: $sharedModule"
}
Import-Module $sharedModule -Force

try {
    Write-Log "=== STARTING END-TO-END DEPLOYMENT ===" "INFO"

    # --- 1. Initialize Minikube ---
    Write-Log "Step 1: Initializing Minikube..." "INFO"
    & "$PSScriptRoot\minikube.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Minikube initialization failed" }

    # --- 2. Deploy Platform ---
    Write-Log "Step 2: Deploying Platform..." "INFO"
    & "$PSScriptRoot\platform.ps1" -Namespace $Namespace -EnvFile $EnvFile -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "Platform deployment failed" }
    
    # --- 3. Deploy Backend Services ---
    Write-Log "Step 3: Deploying Backend Services..." "INFO"
    & "$PSScriptRoot\backend.ps1" -Namespace $Namespace -EnvFile $EnvFile -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "Backend deployment failed" }

    # --- 4. Deploy Frontend ---
    Write-Log "Step 4: Deploying Frontend..." "INFO"
    & "$PSScriptRoot\frontend.ps1" -Namespace $Namespace -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "Frontend deployment failed" }

    Write-Log "=== END-TO-END DEPLOYMENT SUCCESSFUL ===" "SUCCESS"
}
catch {
    Write-Log "A deployment step failed: $_" "ERROR"
    exit 1
}