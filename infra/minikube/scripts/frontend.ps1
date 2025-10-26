<#
.SYNOPSIS
    Deploys the frontend web application to a Minikube cluster.

.DESCRIPTION
    This script builds the frontend Docker image, loads it into Minikube,
    and deploys it using Helm to the specified Kubernetes namespace.

.PARAMETER Namespace
    Kubernetes namespace for the deployment (default: ora).

.PARAMETER ProjectRoot
    Root directory of the project.
#>

param(
    [string]$Namespace = "ora",
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\.." -ErrorAction Stop).Path
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
# FRONTEND DEPLOYMENT FUNCTIONS
#=======================================================================

function Test-FrontendPrerequisites {
    <#
    .SYNOPSIS
        Validates that all required tools and paths exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    Write-Log "Validating deployment prerequisites..." "INFO"
    
    Test-ToolsInstalled -Tools @("docker", "kubectl", "helm", "minikube")
    Test-ProjectRoot -ProjectRoot $ProjectRoot
    
    Write-Log "Prerequisites validated successfully" "SUCCESS"
}

function Get-FrontendPaths {
    <#
    .SYNOPSIS
        Returns validated paths for frontend deployment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $frontendPath = Join-Path $ProjectRoot "frontend\web"
    $chartPath = Join-Path $frontendPath "k8s"

    if (-not (Test-Path $frontendPath)) {
        throw "Frontend path not found: $frontendPath"
    }

    if (-not (Test-Path $chartPath)) {
        throw "Helm chart path not found: $chartPath"
    }

    if (-not (Test-Path (Join-Path $chartPath "Chart.yaml"))) {
        throw "Helm Chart.yaml not found in: $chartPath"
    }

    Write-Log "Frontend paths validated" "SUCCESS"

    return @{
        Frontend = $frontendPath
        Chart    = $chartPath
    }
}

function New-FrontendImage {
    <#
    .SYNOPSIS
        Builds and loads the frontend Docker image.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageName,
        
        [Parameter(Mandatory)]
        [string]$ImageTag,
        
        [Parameter(Mandatory)]
        [string]$BuildPath
    )

    Write-Log "Building frontend Docker image..." "INFO"
    
    $fullTag = New-DockerImage `
        -ImageName $ImageName `
        -BuildPath $BuildPath `
        -Tag $ImageTag
    
    Import-MinikubeImage -ImageTag $fullTag
    
    return $fullTag
}

function Install-FrontendChart {
    <#
    .SYNOPSIS
        Installs the frontend Helm chart.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartPath,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [string]$ReleaseName = "web-service"
    )

    Write-Log "Installing frontend Helm chart..." "INFO"
    
    Update-HelmDependencies -ChartPath $ChartPath
    
    Install-HelmRelease `
        -ReleaseName $ReleaseName `
        -ChartPath $ChartPath `
        -Namespace $Namespace
    
    Write-Log "Frontend Helm chart installed" "SUCCESS"
}

function Invoke-FrontendDeployment {
    <#
    .SYNOPSIS
        Main orchestration function for frontend deployment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [Parameter(Mandatory)]
        [string]$ImageName,
        
        [Parameter(Mandatory)]
        [string]$ImageTag
    )

    # Get and validate paths
    $paths = Get-FrontendPaths -ProjectRoot $ProjectRoot

    # Build and load image
    $imageTag = New-FrontendImage `
        -ImageName $ImageName `
        -ImageTag $ImageTag `
        -BuildPath $paths.Frontend

    # Install Helm chart
    Install-FrontendChart `
        -ChartPath $paths.Chart `
        -Namespace $Namespace

    Write-Log "Frontend deployment completed successfully!" "SUCCESS"
}

#=======================================================================
# MAIN EXECUTION
#=======================================================================

try {
    Write-Log "=== Frontend Deployment ===" "INFO"

    # Validate prerequisites
    Test-FrontendPrerequisites -ProjectRoot $ProjectRoot

    # Execute deployment
    Invoke-FrontendDeployment `
        -ProjectRoot $ProjectRoot `
        -Namespace $Namespace `
        -ImageName "ora-web" `
        -ImageTag "latest"

    Write-Log "Frontend deployed successfully!" "SUCCESS"
}
catch {
    Write-Log "Frontend deployment failed: $_" "ERROR"
    exit 1
}