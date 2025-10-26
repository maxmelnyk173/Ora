<#
.SYNOPSIS
    Deploys backend microservices to a Minikube cluster.

.DESCRIPTION
    This script builds Docker images, runs database migrations, and deploys
    backend services using Helm charts to a specified Kubernetes namespace.

.PARAMETER Namespace
    Kubernetes namespace for deployments (default: ora).

.PARAMETER EnvFile
    Path to the .env file containing environment variables.

.PARAMETER ProjectRoot
    Root directory of the project.
#>

param(
    [string]$Namespace = "ora",
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [string]$ProjectRoot = $(Resolve-Path "$PSScriptRoot\..\..\..")
)

#=======================================================================
# IMPORT SHARED FUNCTIONS
#=======================================================================

$sharedModule = Join-Path $PSScriptRoot "shared.psm1"
if (-not (Test-Path $sharedModule)) {
    throw "Shared functions module not found at: $sharedModule"
}
Import-Module $sharedModule -Force

#=======================================================================
# SERVICE DEPLOYMENT FUNCTIONS
#=======================================================================

function Test-ServicePrerequisites {
    <#
    .SYNOPSIS
        Validates that all required tools and paths exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [string]$EnvFile
    )

    Write-Log "Validating deployment prerequisites..." "INFO"
    
    Test-ToolsInstalled -Tools @("docker", "kubectl", "helm", "minikube")
    Test-ProjectRoot -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path $EnvFile)) {
        throw "Environment file not found at: $EnvFile"
    }
    
    Write-Log "Prerequisites validated successfully" "SUCCESS"
}

function Initialize-DatabasePortForward {
    <#
    .SYNOPSIS
        Sets up port-forwarding to PostgreSQL pod.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Setting up PostgreSQL port-forward..." "INFO"
    
    $pgPod = Get-KubernetesPod -LabelSelector "app.kubernetes.io/name=postgresql" -Namespace $Namespace
    $job = Start-PortForward -PodName $pgPod -Namespace $Namespace -LocalPort "5433" -RemotePort "5432"
    
    return $job
}

function Get-ServiceConfiguration {
    <#
    .SYNOPSIS
        Returns the configuration for all backend services.
    #>
    return @(
        @{ 
            Name          = "auth"
            EnvPrefix     = "AUTH"
            SkipMigration = $true
        },
        @{ 
            Name      = "profile"
            EnvPrefix = "PROFILE"
        },
        @{ 
            Name      = "learning"
            EnvPrefix = "LEARNING"
        },
        @{ 
            Name      = "scheduling"
            EnvPrefix = "SCHEDULING"
        },
        @{ 
            Name      = "payment"
            EnvPrefix = "PAYMENT"
        }
    )
}

function Invoke-ServiceMigration {
    <#
    .SYNOPSIS
        Runs database migrations for a service if applicable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        
        [Parameter(Mandatory)]
        [string]$ServicePath,
        
        [hashtable]$DbCredentials,
        
        [switch]$Skip
    )

    if ($Skip) {
        Write-Log "Skipping migrations for $ServiceName (flag set)" "WARN"
        return
    }

    if ($null -eq $DbCredentials) {
        Write-Log "No database credentials provided for $ServiceName, skipping migration" "WARN"
        return
    }

    $migrationPath = Join-Path $ServicePath "migrations\changelog"
    
    if (-not (Test-Path $migrationPath)) {
        Write-Log "No migration path found for $ServiceName, skipping" "WARN"
        return
    }

    Invoke-LiquibaseMigration `
        -ChangelogPath $migrationPath `
        -DatabaseName $DbCredentials.Name `
        -DatabaseUser $DbCredentials.User `
        -DatabasePassword $DbCredentials.Password
}

function Publish-BackendService {
    <#
    .SYNOPSIS
        Deploys a single backend service (build, load, helm install).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [hashtable]$DbCredentials,
        
        [switch]$SkipMigration
    )

    Write-Log "=== Deploying $ServiceName service ===" "INFO"
    
    $servicePath = Join-Path $ProjectRoot "backend\$ServiceName"
    
    if (-not (Test-Path $servicePath)) {
        throw "Service path not found: $servicePath"
    }

    # Step 1: Run migrations
    Invoke-ServiceMigration `
        -ServiceName $ServiceName `
        -ServicePath $servicePath `
        -DbCredentials $DbCredentials `
        -Skip:$SkipMigration

    # Step 2: Build and load Docker image
    $imageName = "ora-$($ServiceName.ToLower())"
    $imageTag = New-DockerImage -ImageName $imageName -BuildPath $servicePath -Tag "latest"
    Import-MinikubeImage -ImageTag $imageTag

    # Step 3: Deploy Helm chart
    $chartPath = Join-Path $servicePath "k8s"
    
    if (-not (Test-Path (Join-Path $chartPath "Chart.yaml"))) {
        Write-Log "Helm chart not found for $ServiceName, skipping Helm deployment" "WARN"
        return
    }

    Update-HelmDependencies -ChartPath $chartPath
    Install-HelmRelease `
        -ReleaseName "$ServiceName-service" `
        -ChartPath $chartPath `
        -Namespace $Namespace
    
    Write-Log "$ServiceName service deployed successfully" "SUCCESS"
}

function Invoke-BackendDeployment {
    <#
    .SYNOPSIS
        Main orchestration function for deploying all backend services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [Parameter(Mandatory)]
        [hashtable]$EnvData,
        
        [Parameter(Mandatory)]
        [array]$Services
    )

    $portForwardJob = $null
    
    try {
        # Setup database port-forward
        $portForwardJob = Initialize-DatabasePortForward -Namespace $Namespace

        # Deploy each service
        foreach ($service in $Services) {
            $deployParams = @{
                ServiceName   = $service.Name
                ProjectRoot   = $ProjectRoot
                Namespace     = $Namespace
                SkipMigration = $service.SkipMigration -eq $true
            }

            # Add database credentials if needed
            if ($service.EnvPrefix -and -not $service.SkipMigration) {
                try {
                    $deployParams.DbCredentials = Get-DatabaseCredentials `
                        -EnvData $EnvData `
                        -ServicePrefix $service.EnvPrefix
                }
                catch {
                    Write-Log "Failed to get database credentials for $($service.Name): $_" "ERROR"
                    throw
                }
            }

            Publish-BackendService @deployParams
        }

        Write-Log "All backend services deployed successfully!" "SUCCESS"
    }
    finally {
        if ($portForwardJob) {
            Stop-PortForward -Job $portForwardJob
        }
    }
}

#=======================================================================
# MAIN EXECUTION
#=======================================================================

try {
    Write-Log "=== Backend Services Deployment ===" "INFO"

    Test-ServicePrerequisites -ProjectRoot $ProjectRoot -EnvFile $EnvFile

    $envData = Get-EnvironmentData -FilePath $EnvFile

    $services = Get-ServiceConfiguration

    Invoke-BackendDeployment `
        -ProjectRoot $ProjectRoot `
        -Namespace $Namespace `
        -EnvData $envData `
        -Services $services

    Write-Log "Backend deployment completed successfully!" "SUCCESS"
}
catch {
    Write-Log "Backend deployment failed: $_" "ERROR"
    exit 1
}