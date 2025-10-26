<#
.SYNOPSIS
    Bootstraps a local Minikube-based platform environment using Helm and Kubernetes secrets.

.DESCRIPTION
    This script sets up namespaces, installs Prometheus CRDs, applies secrets from .env,
    and deploys a full Helm-based platform stack.

.PARAMETER Namespace
    Kubernetes namespace to use for all operations (default: ora).

.PARAMETER EnvFile
    Path to the .env file containing environment variables.

.PARAMETER ProjectRoot
    Root directory of the project (defaults to script root traversal).
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
# KUBERNETES SECRET FUNCTIONS
#=======================================================================

function New-KubernetesSecretYaml {
    <#
    .SYNOPSIS
        Generates YAML for a Kubernetes secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [hashtable]$StringData,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    $yaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: $Name
  namespace: $Namespace
type: Opaque
stringData:
"@

    foreach ($key in $StringData.Keys) {
        $value = $StringData[$key] -replace "`r", ""
        if ($null -eq $value) { $value = "" }

        if ($value -match "`n") {
            $indented = ($value -split "`n" | ForEach-Object { "    $_" }) -join "`n"
            $yaml += "`n  ${key}: |`n$indented"
        }
        else {
            $escaped = ($value -replace '\\', '\\\\') -replace '"', '\"'
            $yaml += "`n  ${key}: `"$escaped`""
        }
    }

    return $yaml
}

function Set-KubernetesSecret {
    <#
    .SYNOPSIS
        Creates or updates a Kubernetes secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [hashtable]$StringData,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Applying secret: $Name..." "INFO"
    
    $secretYaml = New-KubernetesSecretYaml -Name $Name -Namespace $Namespace -StringData $StringData

    try {
        $output = $secretYaml | kubectl apply -f - 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "kubectl apply failed"
        }
        
        Write-Log "Secret applied: $Name" "SUCCESS"
    }
    catch {
        Write-Log "Failed to apply secret ${Name}: $_" "ERROR"
        throw
    }
}

#=======================================================================
# DATABASE CONFIGURATION FUNCTIONS
#=======================================================================

function Get-DatabaseConfigurations {
    <#
    .SYNOPSIS
        Extracts database configurations for multiple services from environment data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvData,
        
        [Parameter(Mandatory)]
        [string[]]$Services
    )

    Write-Log "Extracting database configurations..." "INFO"
    
    $dbConfigs = @{}
    
    foreach ($svc in $Services) {
        $dbNameKey = "${svc}_DB_NAME"
        $dbUserKey = "${svc}_DB_USER"
        $dbPassKey = "${svc}_DB_PASS"

        foreach ($key in @($dbNameKey, $dbUserKey, $dbPassKey)) {
            if (-not $EnvData.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($EnvData[$key])) {
                throw "Missing environment variable: '$key'"
            }
        }

        $dbConfigs[$svc.ToLower()] = @{
            Name     = $EnvData[$dbNameKey]
            User     = $EnvData[$dbUserKey]
            Password = $EnvData[$dbPassKey]
        }
    }
    
    Write-Log "Extracted configurations for $($dbConfigs.Count) services" "SUCCESS"
    return $dbConfigs
}

function New-PostgresInitScript {
    <#
    .SYNOPSIS
        Creates a PostgreSQL initialization script for multiple databases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DbConfigs
    )

    $header = @'
#!/bin/bash
set -e
echo "Creating databases from map..."
export PGPASSWORD="${POSTGRES_PASSWORD}"

create_db_and_user() {
    local DB_NAME=$1
    local DB_USER=$2
    local DB_PASS=$3

    echo "Checking user $DB_USER..."
    if ! psql -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" | grep -q 1; then
        echo "Creating user $DB_USER"
        psql -U postgres -c "CREATE USER \"$DB_USER\" WITH ENCRYPTED PASSWORD '$DB_PASS';"
    fi

    echo "Checking database $DB_NAME..."
    if ! psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
        echo "Creating database $DB_NAME"
        psql -U postgres -c "CREATE DATABASE \"$DB_NAME\" WITH OWNER = \"$DB_USER\";"
    fi

    echo "Granting privileges on $DB_NAME to $DB_USER"
    psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"
}
'@

    $builder = [System.Text.StringBuilder]::new()
    $builder.AppendLine($header) | Out-Null

    foreach ($svc in $DbConfigs.Keys) {
        $config = $DbConfigs[$svc]
        $builder.AppendLine("create_db_and_user `"$($config.Name)`" `"$($config.User)`" `"$($config.Password)`"") | Out-Null
    }

    return @{ "01-create-dbs.sh" = $builder.ToString() }
}

function New-DatabaseSecrets {
    <#
    .SYNOPSIS
        Creates Kubernetes secrets for database credentials.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DbConfigs,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Creating database secrets..." "INFO"
    
    foreach ($svc in $DbConfigs.Keys) {
        $config = $DbConfigs[$svc]
        $secretName = "$svc-db-secret"

        Set-KubernetesSecret -Name $secretName -Namespace $Namespace -StringData @{
            "name"     = $config.Name
            "username" = $config.User
            "password" = $config.Password
        }
    }
    
    Write-Log "Database secrets created" "SUCCESS"
}

#=======================================================================
# PLATFORM SETUP FUNCTIONS
#=======================================================================

function Test-PlatformPrerequisites {
    <#
    .SYNOPSIS
        Validates all prerequisites for platform deployment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [string]$EnvFile
    )

    Write-Log "Validating platform prerequisites..." "INFO"
    
    Test-ToolsInstalled -Tools @("kubectl", "helm", "minikube")
    Test-ProjectRoot -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path $EnvFile)) {
        throw "Environment file not found at: $EnvFile"
    }
    
    Write-Log "Prerequisites validated successfully" "SUCCESS"
}

function Add-HelmRepositories {
    <#
    .SYNOPSIS
        Adds and updates required Helm repositories.
    #>
    Write-Log "Setting up Helm repositories..." "INFO"
    
    $repos = @{
        "bitnami"              = "https://charts.bitnami.com/bitnami"
        "grafana"              = "https://grafana.github.io/helm-charts"
        "ingress-nginx"        = "https://kubernetes.github.io/ingress-nginx"
        "prometheus-community" = "https://prometheus-community.github.io/helm-charts"
        "opentelemetry-helm"   = "https://open-telemetry.github.io/opentelemetry-helm-charts"
    }

    foreach ($repo in $repos.GetEnumerator()) {
        $output = helm repo add $repo.Key $repo.Value 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            Write-Log "Repository $($repo.Key) may already exist" "WARN"
        }
    }
    
    helm repo update 2>&1 | Out-Null
    Write-Log "Helm repositories configured" "SUCCESS"
}

function Enable-MinikubeAddons {
    <#
    .SYNOPSIS
        Enables required Minikube addons.
    #>
    Write-Log "Enabling Minikube addons..." "INFO"
    
    $output = minikube addons enable metrics-server 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        Write-Log "Metrics server may already be enabled" "WARN"
    }
    else {
        Write-Log "Metrics server enabled" "SUCCESS"
    }
}

function New-KubernetesNamespace {
    <#
    .SYNOPSIS
        Creates a Kubernetes namespace if it doesn't exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Ensuring namespace exists: $Namespace" "INFO"
    
    $output = kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        throw "Failed to create namespace: $Namespace"
    }
    
    Write-Log "Namespace ready: $Namespace" "SUCCESS"
}

function Install-PrometheusCrds {
    <#
    .SYNOPSIS
        Installs Prometheus Operator CRDs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Installing Prometheus CRDs..." "INFO"
    
    $output = helm install prometheus-crds prometheus-community/prometheus-operator-crds `
        --version 22.0.2 `
        -n $Namespace 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "$($output)" "ERROR"
        Write-Log "Prometheus CRDs may already be installed" "WARN"
    }
    else {
        Write-Log "Prometheus CRDs installed" "SUCCESS"
    }
}

function New-ApplicationSecrets {
    <#
    .SYNOPSIS
        Creates secrets for platform applications.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvData,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Creating application secrets..." "INFO"

    $secretsToCreate = @(
        @{ 
            Name = "postgres-auth"
            Data = @{ "admin-password" = $EnvData["POSTGRES_PASSWORD"] }
        },
        @{ 
            Name = "keycloak-auth"
            Data = @{ "admin-password" = $EnvData["KEYCLOAK_ADMIN_PASSWORD"] }
        },
        @{ 
            Name = "rabbitmq-auth"
            Data = @{ "admin-password" = $EnvData["RABBITMQ_PASSWORD"] }
        },
        @{ 
            Name = "grafana-auth"
            Data = @{ 
                "admin-user"     = $EnvData["GRAFANA_USER"]
                "admin-password" = $EnvData["GRAFANA_PASSWORD"]
            }
        }
    )

    foreach ($secret in $secretsToCreate) {
        Set-KubernetesSecret -Name $secret.Name -StringData $secret.Data -Namespace $Namespace
    }
    
    Write-Log "Application secrets created" "SUCCESS"
}

function New-PostgresInitSecrets {
    <#
    .SYNOPSIS
        Creates PostgreSQL initialization secrets for all services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvData,
        
        [Parameter(Mandatory)]
        [string]$Namespace
    )

    Write-Log "Creating PostgreSQL initialization secrets..." "INFO"

    $services = @("KEYCLOAK", "PROFILE", "LEARNING", "SCHEDULING", "PAYMENT")
    
    $dbConfigs = Get-DatabaseConfigurations -EnvData $EnvData -Services $services

    $initScripts = New-PostgresInitScript -DbConfigs $dbConfigs

    Set-KubernetesSecret -Name "postgres-init-script" -Namespace $Namespace -StringData $initScripts

    New-DatabaseSecrets -DbConfigs $dbConfigs -Namespace $Namespace
    
    Write-Log "PostgreSQL initialization secrets created" "SUCCESS"
}

function New-CaCertificateSecret {
    <#
    .SYNOPSIS
        Creates a Kubernetes secret containing the mkcert root CA (key: rootCA.crt).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace,

        [Parameter(Mandatory)]
        [string]$CertPath
    )

    Write-Log "Creating CA certificate secret from: $CertPath" "INFO"

    if (-not (Test-Path $CertPath)) {
        throw "CA certificate file not found at: $CertPath"
    }

    $secretName = "root-ca-cert"
    $certData = Get-Content -Raw -Path $CertPath
    $certData = $certData -replace "`r`n", "`n"
    
    Set-KubernetesSecret -Name $secretName -Namespace $Namespace -StringData @{
        "rootCA.crt" = $certData
    }

    Write-Log "CA certificate secret created: $secretName" "SUCCESS"
}

function New-IngressTlsSecret {
    <#
    .SYNOPSIS
        Creates a Kubernetes TLS secret for ingress-nginx.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace,

        [Parameter(Mandatory)]
        [string]$CertPath,

        [Parameter(Mandatory)]
        [string]$KeyPath
    )

    Write-Log "Creating ingress-nginx TLS secret..." "INFO"

    if (-not (Test-Path $CertPath)) {
        throw "Certificate file not found: $CertPath"
    }
    if (-not (Test-Path $KeyPath)) {
        throw "Private key file not found: $KeyPath"
    }

    $secretName = "nginx-default-cert"
    $certContent = Get-Content -Raw -Path $CertPath
    $keyContent = Get-Content -Raw -Path $KeyPath

    # Use TLS secret type
    $yaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: $secretName
  namespace: $Namespace
type: kubernetes.io/tls
stringData:
  tls.crt: |
$(($certContent -split "`n" | ForEach-Object { "    $_" }) -join "`n")
  tls.key: |
$(($keyContent -split "`n" | ForEach-Object { "    $_" }) -join "`n")
"@

    try {
        $output = $yaml | kubectl apply -f - 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "kubectl apply failed"
        }

        Write-Log "Ingress TLS secret created: $secretName" "SUCCESS"
    }
    catch {
        Write-Log "Failed to create ingress TLS secret: $_" "ERROR"
        throw
    }
}

function Update-CoreDnsRewrite {
    <#
    .SYNOPSIS
        Ensures CoreDNS ConfigMap contains the rewrite rule for Keycloak,
        inserting it right after the 'ready' directive.
    #>
    [CmdletBinding()]
    param(
        [string]$FromHost = "keycloak.127.0.0.1.nip.io",
        [string]$ToSvc = "platform-ingress-nginx-controller.ora.svc.cluster.local"
    )

    $configMapName = "coredns"
    $configMapNs = "kube-system"
    $rewriteRule = "        rewrite name exact $FromHost $ToSvc"

    try {
        Write-Host "Fetching current CoreDNS ConfigMap..." -ForegroundColor Cyan
        $yaml = kubectl get configmap $configMapName -n $configMapNs -o yaml
        if ($LASTEXITCODE -ne 0) { throw "Failed to get CoreDNS ConfigMap" }

        if ($yaml -match [regex]::Escape($rewriteRule.Trim())) {
            Write-Host "Rewrite rule already present. Skipping." -ForegroundColor Green
        }
        else {
            Write-Host "Injecting rewrite rule after 'ready'..." -ForegroundColor Yellow

            $lines = $yaml -split "`r?`n"
            $newLines = @()
            $inserted = $false

            foreach ($line in $lines) {
                $newLines += $line
                if ($line -match "^\s*ready") {
                    $newLines += $rewriteRule
                    $inserted = $true
                }
            }

            if (-not $inserted) {
                throw "Could not find 'ready' directive to insert rewrite rule"
            }

            $tmpFile = [System.IO.Path]::GetTempFileName() + ".yaml"
            $newLines -join "`n" | Out-File -Encoding utf8 $tmpFile

            kubectl replace -f $tmpFile
            if ($LASTEXITCODE -ne 0) { throw "Failed to replace updated ConfigMap" }
        }

        Write-Host "Restarting CoreDNS..." -ForegroundColor Cyan
        kubectl -n $configMapNs rollout restart deployment $configMapName
        if ($LASTEXITCODE -ne 0) { throw "Failed to restart CoreDNS" }

        Write-Host "CoreDNS rewrite rule applied successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        throw
    }
}

function Install-PlatformChart {
    <#
    .SYNOPSIS
        Installs the main platform Helm chart with all value files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [Parameter(Mandatory)]
        [string]$ChartPath
    )
    
    Write-Log "Installing platform Helm chart..." "INFO"

    $valueFiles = @(
        "services/postgresql-values.yaml",
        "services/keycloak-values.yaml",
        "services/rabbitmq-values.yaml",
        "services/otel-values.yaml",
        "services/prometheus-values.yaml",
        "services/loki-values.yaml",
        "services/tempo-values.yaml",
        "services/grafana-values.yaml",
        "services/ingress-nginx-values.yaml",
        "values.yaml"
    )

    # Build helm arguments
    $helmArgs = @("install", "platform", ".", "-n", $Namespace)
    foreach ($file in $valueFiles) {
        $fullPath = Join-Path $ChartPath $file
        if (-not (Test-Path $fullPath)) {
            Write-Log "Value file not found: $file, skipping" "WARN"
            continue
        }
        $helmArgs += "-f", $file
    }

    Push-Location $ChartPath
    try {
        $output = helm @helmArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($output)" "ERROR"
            throw "Platform Helm installation failed"
        }
        
        Write-Log "Platform Helm chart installed" "SUCCESS"
    }
    finally {
        Pop-Location
    }
}

function Initialize-PlatformEnvironment {
    <#
    .SYNOPSIS
        Main orchestration function for platform setup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Namespace,
        
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory)]
        [hashtable]$EnvData
    )

    # Setup infrastructure
    Add-HelmRepositories
    Enable-MinikubeAddons
    New-KubernetesNamespace -Namespace $Namespace
    Install-PrometheusCrds -Namespace $Namespace
    
    # Create secrets
    New-ApplicationSecrets -EnvData $EnvData -Namespace $Namespace
    New-PostgresInitSecrets -EnvData $EnvData -Namespace $Namespace

    # Add CA certificate secret
    $caCertPath = Join-Path $ProjectRoot "certs\rootCA.pem"
    New-CaCertificateSecret -Namespace $Namespace -CertPath $caCertPath

    # Add ingress TLS secret
    $tlsCertPath = Join-Path $ProjectRoot "certs\cert.pem"
    $tlsKeyPath = Join-Path $ProjectRoot "certs\cert-key.pem"
    New-IngressTlsSecret -Namespace $Namespace -CertPath $tlsCertPath -KeyPath $tlsKeyPath

    # Update CoreDNS for Keycloak rewrite
    Update-CoreDnsRewrite

    # Deploy platform
    $chartDir = Join-Path $ProjectRoot "infra\minikube\helm-charts\platform"
    
    if (-not (Test-Path $chartDir)) {
        throw "Platform chart directory not found: $chartDir"
    }
    
    Install-PlatformChart -Namespace $Namespace -ChartPath $chartDir
    
    Write-Log "Platform environment initialized successfully!" "SUCCESS"
}

#=======================================================================
# MAIN EXECUTION
#=======================================================================

try {
    Write-Log "=== Platform Environment Setup ===" "INFO"

    Test-PlatformPrerequisites -ProjectRoot $ProjectRoot -EnvFile $EnvFile

    $envData = Get-EnvironmentData -FilePath $EnvFile

    Initialize-PlatformEnvironment `
        -Namespace $Namespace `
        -ProjectRoot $ProjectRoot `
        -EnvData $envData

    Write-Log "Platform deployment completed successfully!" "SUCCESS"
}
catch {
    Write-Log "Platform deployment failed: $_" "ERROR"
    exit 1
}