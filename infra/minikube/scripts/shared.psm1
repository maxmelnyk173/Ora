#=======================================================================
# SHARED UTILITY FUNCTIONS
# Common functions used across deployment scripts
#=======================================================================

#=======================================================================
# LOGGING UTILITIES
#=======================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Logs a message with timestamp and severity level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $msg = if ($null -eq $Message) { "<no message>" } else { $Message -join "`n" }
    $timestamp = (Get-Date).ToString('u')
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
    }
    Write-Host "[$timestamp][$Level] $msg" -ForegroundColor $color
}

#=======================================================================
# ENVIRONMENT & VALIDATION
#=======================================================================

function Get-EnvironmentData {
    <#
    .SYNOPSIS
        Loads and parses environment variables from a .env file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        throw ".env file not found at $FilePath"
    }

    $envData = @{}
    Get-Content $FilePath | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim('"').Trim()
            if ($envData.ContainsKey($key)) {
                Write-Log "Duplicate key '$key' in $FilePath (overwriting)" "WARN"
            }
            $envData[$key] = $value
        }
    }

    Write-Log "Environment file loaded: $FilePath" "SUCCESS"
    return $envData
}

function Test-ToolsInstalled {
    <#
    .SYNOPSIS
        Verifies that required command-line tools are available.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Tools
    )

    $missing = @()
    foreach ($tool in $Tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            $missing += $tool
        }
    }

    if ($missing.Count -gt 0) {
        throw "Required tools not found: $($missing -join ', ')"
    }

    Write-Log "All required tools detected: $($Tools -join ', ')" "SUCCESS"
}

function Test-ProjectRoot {
    <#
    .SYNOPSIS
        Validates that the project root directory exists.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    if (-not (Test-Path $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot. Please provide -ProjectRoot explicitly."
    }

    Write-Log "Project root validated: $ProjectRoot" "SUCCESS"
}

#=======================================================================
# DOCKER OPERATIONS
#=======================================================================

function New-DockerImage {
    <#
    .SYNOPSIS
        Builds a Docker image from a specified path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageName,
        
        [Parameter(Mandatory)]
        [string]$BuildPath,
        
        [string]$Tag = "latest"
    )

    $fullTag = "${ImageName}:${Tag}"
    
    Write-Log "Building Docker image: $fullTag" "INFO"
    
    Push-Location $BuildPath
    try {
        $output = docker build -t $fullTag . 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "Docker build failed for $fullTag"
        }
        Write-Log "Docker image built: $fullTag" "SUCCESS"
        return $fullTag
    }
    finally {
        Pop-Location
    }
}

function Import-MinikubeImage {
    <#
    .SYNOPSIS
        Loads a Docker image into Minikube's image cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageTag
    )

    Write-Log "Loading image into Minikube: $ImageTag" "INFO"
    $output = minikube image load $ImageTag 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Failed to load image into Minikube: $ImageTag"
    }
    
    Write-Log "Image loaded into Minikube: $ImageTag" "SUCCESS"
}

#=======================================================================
# HELM OPERATIONS
#=======================================================================

function Update-HelmDependencies {
    <#
    .SYNOPSIS
        Updates Helm chart dependencies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartPath
    )

    Write-Log "Updating Helm dependencies..." "INFO"
    
    Push-Location $ChartPath
    try {
        $output = helm dependency update 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "Helm dependency update failed"
        }
        Write-Log "Helm dependencies updated" "SUCCESS"
    }
    finally {
        Pop-Location
    }
}

function Install-HelmRelease {
    <#
    .SYNOPSIS
        Installs a Helm release with specified values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseName,
        
        [Parameter(Mandatory)]
        [string]$ChartPath,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [string]$ValuesFile = "values.yaml",
        
        [hashtable]$SetValues = @{}
    )

    Write-Log "Installing Helm release: $ReleaseName" "INFO"
    
    Push-Location $ChartPath
    try {
        $helmArgs = @("install", $ReleaseName, ".", "-n", $Namespace, "-f", $ValuesFile)
        
        foreach ($key in $SetValues.Keys) {
            $helmArgs += "--set"
            $helmArgs += "$key=$($SetValues[$key])"
        }

        $output = helm @helmArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "Helm installation failed for $ReleaseName"
        }
        
        Write-Log "Helm release installed: $ReleaseName" "SUCCESS"
    }
    finally {
        Pop-Location
    }
}

#=======================================================================
# KUBERNETES OPERATIONS
#=======================================================================

function Get-KubernetesPod {
    <#
    .SYNOPSIS
        Retrieves the first pod matching a label selector.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LabelSelector,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    $pod = kubectl get pods -n $Namespace -l $LabelSelector -o jsonpath="{.items[0].metadata.name}" 2>&1
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pod)) {
        Write-Log "$($output)" "ERROR"
        throw "Could not find pod with label '$LabelSelector' in namespace '$Namespace'"
    }

    return $pod
}

function Start-PortForward {
    <#
    .SYNOPSIS
        Starts a kubectl port-forward as a background job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PodName,
        
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [Parameter(Mandatory)]
        [string]$LocalPort,
        
        [Parameter(Mandatory)]
        [string]$RemotePort,
        
        [int]$WaitSeconds = 5
    )

    Write-Log "Starting port-forward: localhost:${LocalPort} -> ${PodName}:${RemotePort}" "INFO"
    
    $job = Start-Job {
        kubectl port-forward pod/$using:PodName $using:LocalPort`:$using:RemotePort -n $using:Namespace
    }
    
    Start-Sleep -Seconds $WaitSeconds
    Write-Log "Port-forward established (localhost:${LocalPort} -> ${PodName}:${RemotePort})" "SUCCESS"
    
    return $job
}

function Stop-PortForward {
    <#
    .SYNOPSIS
        Stops a port-forward background job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Job]$Job
    )

    if ($null -eq $Job) {
        return
    }

    Write-Log "Stopping port-forward job..." "INFO"
    Stop-Job $Job -ErrorAction SilentlyContinue
    Remove-Job $Job -ErrorAction SilentlyContinue
    Write-Log "Port-forward job stopped" "SUCCESS"
}

#=======================================================================
# DATABASE OPERATIONS
#=======================================================================

function Invoke-LiquibaseMigration {
    <#
    .SYNOPSIS
        Runs Liquibase database migrations using Docker.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangelogPath,
        
        [Parameter(Mandatory)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory)]
        [string]$DatabaseUser,
        
        [Parameter(Mandatory)]
        [SecureString]$DatabasePassword,
        
        [string]$DatabaseHost = "host.docker.internal",
        
        [string]$DatabasePort = "5433",
        
        [string]$ChangelogFile = "db.changelog-master.xml"
    )

    if (-not (Test-Path $ChangelogPath)) {
        Write-Log "Migration path not found: $ChangelogPath, skipping" "WARN"
        return
    }

    Write-Log "Running database migrations for $DatabaseName..." "INFO"

    if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Command ConvertFrom-SecureString).Parameters.ContainsKey("AsPlainText")) {
        $plainPassword = ConvertFrom-SecureString $DatabasePassword -AsPlainText
    }
    else {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword)
        )
    }

    $dockerArgs = @(
        "run", "--rm",
        "-v", "${ChangelogPath}:/liquibase/changelog",
        "liquibase/liquibase:4.31.1-alpine",
        "--search-path=/liquibase/changelog",
        "--changelog-file=$ChangelogFile",
        "--url=jdbc:postgresql://${DatabaseHost}:${DatabasePort}/${DatabaseName}",
        "--username=$DatabaseUser",
        "--password=$plainPassword",
        "update"
    )

    $output = docker @dockerArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Database migration failed for $DatabaseName"
    }

    Write-Log "Database migrations completed for $DatabaseName" "SUCCESS"
}

function Get-DatabaseCredentials {
    <#
    .SYNOPSIS
        Extracts database credentials from environment data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvData,
        
        [Parameter(Mandatory)]
        [string]$ServicePrefix
    )

    $dbNameKey = "${ServicePrefix}_DB_NAME"
    $dbUserKey = "${ServicePrefix}_DB_USER"
    $dbPassKey = "${ServicePrefix}_DB_PASS"

    foreach ($key in @($dbNameKey, $dbUserKey, $dbPassKey)) {
        if (-not $EnvData.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($EnvData[$key])) {
            throw "Missing environment variable: '$key'"
        }
    }

    return @{
        Name     = $EnvData[$dbNameKey]
        User     = $EnvData[$dbUserKey]
        Password = ConvertTo-SecureString $EnvData[$dbPassKey] -AsPlainText -Force
    }
}

#=======================================================================
# HELM REPOSITORY OPERATIONS
#=======================================================================

function Add-HelmRepository {
    <#
    .SYNOPSIS
        Adds a single Helm repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$Url
    )

    $output = helm repo add $Name $Url 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        Write-Log "Repository $Name may already exist" "WARN"
    }
    else {
        Write-Log "Added Helm repository: $Name" "SUCCESS"
    }
}

function Update-HelmRepositories {
    <#
    .SYNOPSIS
        Updates all Helm repositories.
    #>
    Write-Log "Updating Helm repositories..." "INFO"
    helm repo update 2>&1
    Write-Log "Helm repositories updated" "SUCCESS"
}

#=======================================================================
# VALIDATION HELPERS
#=======================================================================

function Test-PathExists {
    <#
    .SYNOPSIS
        Validates that a path exists and throws if it doesn't.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$ErrorMessage = "Path not found: "
    )

    if (-not (Test-Path $Path)) {
        throw "${ErrorMessage}${Path}"
    }
}

function Get-ValidatedPath {
    <#
    .SYNOPSIS
        Gets and validates a path, returning the full path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        
        [Parameter(Mandatory)]
        [string]$RelativePath,
        
        [string]$Description = "Path"
    )

    $fullPath = Join-Path $BasePath $RelativePath
    Test-PathExists -Path $fullPath -ErrorMessage "$Description not found: "
    return $fullPath
}

#=======================================================================
# EXPORT FUNCTIONS
#=======================================================================

Export-ModuleMember -Function @(
    'Write-Log',
    'Get-EnvironmentData',
    'Test-ToolsInstalled',
    'Test-ProjectRoot',
    'New-DockerImage',
    'Import-MinikubeImage',
    'Update-HelmDependencies',
    'Install-HelmRelease',
    'Get-KubernetesPod',
    'Start-PortForward',
    'Stop-PortForward',
    'Invoke-LiquibaseMigration',
    'Get-DatabaseCredentials',
    'Add-HelmRepository',
    'Update-HelmRepositories',
    'Test-PathExists',
    'Get-ValidatedPath'
)