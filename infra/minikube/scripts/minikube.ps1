<#
.SYNOPSIS
    Initializes a Minikube cluster for local development.

.DESCRIPTION
    This script starts a Minikube cluster with specified resources and
    waits for all system components to be ready.

.PARAMETER Cpus
    Number of CPUs to allocate to Minikube (default: 4).

.PARAMETER Memory
    Memory in MB to allocate to Minikube (default: 7000).

.PARAMETER Driver
    Minikube driver to use (default: docker).

.PARAMETER WaitTimeout
    Timeout in seconds for waiting on resources (default: 180).
#>

param(
    [int]$Cpus = 4,
    [int]$Memory = 7000,
    [string]$Driver = "docker",
    [int]$WaitTimeout = 180
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
# MINIKUBE FUNCTIONS
#=======================================================================

function Test-MinikubePrerequisites {
    <#
    .SYNOPSIS
        Validates that Minikube and kubectl are installed.
    #>
    Write-Log "Validating Minikube prerequisites..." "INFO"
    Test-ToolsInstalled -Tools @("minikube", "kubectl")
    Write-Log "Prerequisites validated successfully" "SUCCESS"
}

function Start-MinikubeCluster {
    <#
    .SYNOPSIS
        Starts the Minikube cluster with specified configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Cpus,
        
        [Parameter(Mandatory)]
        [int]$Memory,
        
        [Parameter(Mandatory)]
        [string]$Driver
    )

    Write-Log "Starting Minikube cluster..." "INFO"
    Write-Log "Configuration: CPUs=$Cpus, Memory=${Memory}MB, Driver=$Driver" "INFO"
    
    $output = minikube start --cpus=$Cpus --memory=$Memory --driver=$Driver 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Failed to start Minikube cluster"
    }
    
    Write-Log "Minikube cluster started" "SUCCESS"
}

function Wait-ClusterInitialization {
    <#
    .SYNOPSIS
        Waits for Minikube cluster to fully initialize.
    #>
    [CmdletBinding()]
    param(
        [int]$InitialDelay = 15
    )

    Write-Log "Waiting ${InitialDelay} seconds for Minikube to initialize..." "INFO"
    Start-Sleep -Seconds $InitialDelay
    Write-Log "Initial wait period completed" "SUCCESS"
}

function Wait-SystemPods {
    <#
    .SYNOPSIS
        Waits for all system pods to be ready.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Write-Log "Waiting for Kubernetes system pods to be ready..." "INFO"
    
    $output = kubectl wait --for=condition=Ready pods --all -n kube-system --timeout="${TimeoutSeconds}s" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Timeout waiting for system pods to be ready"
    }
    
    Write-Log "All system pods are ready" "SUCCESS"
}

function Wait-Nodes {
    <#
    .SYNOPSIS
        Waits for all cluster nodes to be ready.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Write-Log "Waiting for cluster nodes to be ready..." "INFO"
    
    $output = kubectl wait --for=condition=Ready node --all --timeout="${TimeoutSeconds}s" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Timeout waiting for nodes to be ready"
    }
    
    Write-Log "All nodes are ready" "SUCCESS"
}

function Test-ClusterHealth {
    <#
    .SYNOPSIS
        Performs basic health checks on the cluster.
    #>
    Write-Log "Performing cluster health checks..." "INFO"
    
    # Check cluster info
    $output = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Failed to get cluster info"
    }
    
    # Check node status
    $nodeStatuses = kubectl get nodes -o jsonpath="{.items[*].status.conditions[?(@.type=='Ready')].status}"
    if ($nodeStatuses -notmatch 'True') {
        Write-Log "Node readiness status: $nodeStatuses" "ERROR"
        throw "One or more nodes are not Ready"
    }

    Write-Log "Cluster health checks passed" "SUCCESS"
}

function Initialize-MinikubeCluster {
    <#
    .SYNOPSIS
        Main orchestration function for Minikube initialization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Cpus,
        
        [Parameter(Mandatory)]
        [int]$Memory,
        
        [Parameter(Mandatory)]
        [string]$Driver,
        
        [Parameter(Mandatory)]
        [int]$WaitTimeout
    )

    Start-MinikubeCluster -Cpus $Cpus -Memory $Memory -Driver $Driver

    Wait-ClusterInitialization
    Wait-SystemPods -TimeoutSeconds $WaitTimeout
    Wait-Nodes -TimeoutSeconds $WaitTimeout

    Test-ClusterHealth
    
    Write-Log "Minikube cluster is fully ready!" "SUCCESS"
}

#=======================================================================
# MAIN EXECUTION
#=======================================================================

try {
    Write-Log "=== Minikube Cluster Initialization ===" "INFO"

    Test-MinikubePrerequisites

    Initialize-MinikubeCluster `
        -Cpus $Cpus `
        -Memory $Memory `
        -Driver $Driver `
        -WaitTimeout $WaitTimeout

    Write-Log "Minikube initialization completed successfully!" "SUCCESS"
}
catch {
    Write-Log "Minikube initialization failed: $_" "ERROR"
    exit 1
}