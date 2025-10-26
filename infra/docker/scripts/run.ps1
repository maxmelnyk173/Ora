<#
.SYNOPSIS
    Starts a Docker Compose environment with optional database migrations.
.DESCRIPTION
    If -WithMigrations is specified, this script starts the database,
    runs migrations, and then starts all other services.
    Otherwise, it starts all services at once.
.PARAMETER DockerComposeFile
    Path to the docker-compose.yml file. (Default: docker-compose.yml)
.PARAMETER EnvFile
    Path to the .env file. (Default: .env)
.PARAMETER WithMigrations
    Switch to run database migrations after Postgres starts.
.PARAMETER ProjectRoot
    Root directory of the project. (Default: parent directory)
#>
param(
    [string]$DockerComposeFile = "../docker-compose.yml",
    [string]$EnvFile = "../.env",
    [switch]$WithMigrations = $false,
    [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..")
)

#=======================================================================
# HELPER FUNCTIONS
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

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Verifies that required command-line tools are available.
    #>
    [CmdletBinding()]
    param()

    $tool = "docker"
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $tool"
    }
    Write-Log "Prerequisite 'docker' found." "SUCCESS"
}

function Resolve-PathSafe {
    <#
    .SYNOPSIS
        Resolves a path relative to the provided base path (defaults to the script-level ProjectRoot) or the current location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$BasePath = $script:ProjectRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return Resolve-Path $Path -ErrorAction Stop
    }
    
    $candidate = Join-Path $BasePath $Path
    if (Test-Path $candidate) {
        return Resolve-Path $candidate -ErrorAction Stop
    }

    $candidate = Join-Path $PSScriptRoot $Path
    if (Test-Path $candidate) {
        return Resolve-Path $candidate -ErrorAction Stop
    }

    throw "Path not found: $Path"
}

function Import-EnvironmentVariables {
    <#
    .SYNOPSIS
        Loads variables from a .env file into the process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvFilePath
    )

    if (-not (Test-Path $EnvFilePath)) {
        Write-Log "Env file $EnvFilePath not found. Skipping environment loading." "WARN"
        return $null
    }

    Write-Log "Loading environment variables from $EnvFilePath..." "INFO"
    Get-Content $EnvFilePath | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
    Write-Log "Environment variables loaded." "SUCCESS"
}

function Start-DockerComposeServices {
    <#
    .SYNOPSIS
        Runs 'docker compose up' for specified services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFilePath,
        
        [Parameter(Mandatory)]
        [string]$EnvFilePath,
        
        [string[]]$Services
    )

    $serviceList = $Services -join " "
    if ($serviceList) {
        Write-Log "Starting Docker services: $serviceList..." "INFO"
    }
    else {
        Write-Log "Starting all Docker services..." "INFO"
    }

    $dockerArgs = @(
        "compose",
        "-f", $ComposeFilePath,
        "--env-file", $EnvFilePath,
        "up", "-d",
        $Services
    )
    
    $output = docker @dockerArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Docker Compose failed to start services: $serviceList"
    }
    Write-Log "Services started successfully." "SUCCESS"
}

function Stop-DockerComposeServices {
    <#
    .SYNOPSIS
        Runs 'docker compose down' for specified services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFilePath
    )
    
    Write-Log "Stopping Docker services..." "INFO"
    $dockerArgs = @(
        "compose",
        "-f", $ComposeFilePath,
        "down"
    )
    
    $output = docker @dockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Docker Compose failed to stop services."
    }
    Write-Log "Services stopped successfully." "SUCCESS"
}

function Wait-ContainerHealthy {
    <#
    .SYNOPSIS
        Waits for a container to report a 'healthy' status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContainerName,
        
        [int]$TimeoutSeconds = 120,
        [int]$IntervalSeconds = 5
    )

    Write-Log "Waiting for container '$ContainerName' to be healthy..." "INFO"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $status = docker inspect --format='{{.State.Health.Status}}' $ContainerName
        }
        catch {
            Write-Log "Container '$ContainerName' not ready yet..." "INFO"
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        if ($status -eq "healthy") {
            Write-Log "Container '$ContainerName' is healthy." "SUCCESS"
            return
        }

        Write-Log "Container '$ContainerName' status: $status. Waiting..." "INFO"
        Start-Sleep -Seconds $IntervalSeconds
    }

    throw "Timeout: Container '$ContainerName' did not become healthy after $TimeoutSeconds seconds."
}

function Invoke-LiquibaseMigration {
    <#
    .SYNOPSIS
        Runs a single Liquibase migration using Docker.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeAbsolute,
        
        [Parameter(Mandatory)]
        [string]$DbHost,
        
        [Parameter(Mandatory)]
        [string]$DbPort,
        
        [Parameter(Mandatory)]
        [string]$DbName,
        
        [Parameter(Mandatory)]
        [string]$DbUser,
        
        [Parameter(Mandatory)]
        [string]$DbPass
    )

    Write-Log "Running migration for $DbName... $VolumeAbsolute" "INFO"

    $dockerArgs = @(
        "run", "--rm",
        "--network", "ora-net",
        "-v", "${VolumeAbsolute}:/liquibase/changelog",
        "liquibase/liquibase:4.31.1-alpine",
        "--search-path=/liquibase/changelog",
        "--changelog-file=db.changelog-master.xml",
        "--url=jdbc:postgresql://${DbHost}:${DbPort}/${DbName}",
        "--username=$DbUser",
        "--password=$DbPass",
        "update"
    )
    
    docker @dockerArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Migration for $DbName failed."
    }
    
    Write-Log "Migration for $DbName completed successfully." "SUCCESS"
}

function Start-DatabaseMigrations {
    <#
    .SYNOPSIS
        Orchestrates all defined Liquibase migrations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )
    
    Write-Log "Running database migrations with Liquibase..." "INFO"

    # --- DEFINE SERVICES WITH MIGRATIONS HERE ---
    # (Service names must be lowercase and match their path in ../../backend/)
    $servicesWithMigrations = @("profile", "learning", "scheduling", "payment")

    # Dynamically build the list of migration jobs
    $Migrations = foreach ($service in $servicesWithMigrations) {
        $upperService = $service.ToUpper()

        $dbNameEnvVar = "${upperService}_DB_NAME"
        $dbUserEnvVar = "${upperService}_DB_USER"
        $dbPassEnvVar = "${upperService}_DB_PASS"

        $dbName = [System.Environment]::GetEnvironmentVariable($dbNameEnvVar, "Process")
        $dbUser = [System.Environment]::GetEnvironmentVariable($dbUserEnvVar, "Process")
        $dbPass = [System.Environment]::GetEnvironmentVariable($dbPassEnvVar, "Process")

        if (-not $dbName -or -not $dbUser -or -not $dbPass) {
            Write-Log "Missing database credentials for $upperService (e.g., $dbNameEnvVar). Skipping migration." "WARN"
            throw "Database credentials not found for service: $service"
        }

        [PSCustomObject]@{
            VolumeRelative = "backend/$service/migrations/changelog"
            DbName         = $dbName
            DbUser         = $dbUser
            DbPass         = $dbPass
        }
    }

    foreach ($migration in $Migrations) {
        try {
            $VolumeAbsolute = Resolve-PathSafe -Path $migration.VolumeRelative -BasePath $ProjectRoot
        }
        catch {
            Write-Log "Migration path not found for $($migration.DbName): $($migration.VolumeRelative)" "ERROR"
            throw "Migration path resolution failed."
        }

        Invoke-LiquibaseMigration `
            -VolumeAbsolute $VolumeAbsolute `
            -DbHost $env:POSTGRES_HOST `
            -DbPort $env:POSTGRES_PORT `
            -DbName $migration.DbName `
            -DbUser $migration.DbUser `
            -DbPass $migration.DbPass
    }
    
    Write-Log "All migrations completed successfully." "SUCCESS"
}

#=======================================================================
# MAIN EXECUTION
#=======================================================================

try {
    Write-Log "=== Docker Compose Environment Start ===" "INFO"
    
    Test-Prerequisites
    
    $ComposeFilePath = Resolve-PathSafe -Path $DockerComposeFile -BasePath $ProjectRoot
    $EnvFilePath = Resolve-PathSafe -Path $EnvFile -BasePath $ProjectRoot
    
    Import-EnvironmentVariables -EnvFilePath $EnvFilePath

    if ($WithMigrations) {
        Write-Log "Starting services with migration-aware logic..." "INFO"
        
        # Step 1: Start only Postgres and PgAdmin
        Start-DockerComposeServices -ComposeFilePath $ComposeFilePath -EnvFilePath $EnvFilePath -Services @("postgres", "pgadmin")

        # Step 2: Wait for Postgres to be healthy
        # Note: 'pg_db' is the container_name from docker-compose.yml
        Wait-ContainerHealthy -ContainerName "pg_db"

        # Step 3: Run migrations
        Start-DatabaseMigrations -ProjectRoot $ProjectRoot
        
        # Step 4: Start all other services
        Write-Log "Starting all remaining services..." "INFO"
        Start-DockerComposeServices -ComposeFilePath $ComposeFilePath -EnvFilePath $EnvFilePath
        
        Write-Log "All services are up and running." "SUCCESS"
    }
    else {
        Write-Log "Starting all services at once (migrations skipped)." "INFO"
        
        # Start all services defined in the compose file
        Start-DockerComposeServices -ComposeFilePath $ComposeFilePath -EnvFilePath $EnvFilePath
        
        Write-Log "All services are up and running." "SUCCESS"
    }
}
catch {
    Write-Log "Script failed: $_" "ERROR"
    Stop-DockerComposeServices -ComposeFilePath $ComposeFilePath
    exit 1
}