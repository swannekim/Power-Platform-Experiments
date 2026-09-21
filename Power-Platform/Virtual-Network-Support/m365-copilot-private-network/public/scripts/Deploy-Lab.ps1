#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ResourceGroupName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $PublisherEmail,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $PublisherName,
    [ValidatePattern('^[a-z][a-z0-9-]{1,14}[a-z0-9]$')][string] $LabPrefix = 'copilot-private',
    [ValidateNotNullOrEmpty()][string] $DeploymentName = 'm365-copilot-private-network',
    [string] $BootstrapClientIPv4,
    [switch] $SkipBackendUpload,
    [switch] $UploadBackendOnly,
    [switch] $RegisterProviders
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $result = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..1] -join ' ')." }
    if ($result) { ($result -join "`n") | ConvertFrom-Json }
}

function Get-AccessRestrictions {
    param([string] $AppName)
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$AppName/config/web?api-version=2024-04-01"
    Invoke-AzJson @('rest', '--method', 'get', '--url', $url, '--query', 'properties')
}

function Assert-BootstrapRestrictions {
    param($Restrictions, [string] $ClientCidr, [string] $RuleName)
    if ($Restrictions.ipSecurityRestrictionsDefaultAction -ne 'Deny' -or
        $Restrictions.scmIpSecurityRestrictionsDefaultAction -ne 'Deny' -or
        $Restrictions.scmIpSecurityRestrictionsUseMain -ne $false) {
        throw 'Both sites must default to Deny, with separate SCM restrictions.'
    }
    if (@($Restrictions.ipSecurityRestrictions | Where-Object action -eq 'Allow').Count -ne 0) {
        throw 'The main site must have no public Allow rules.'
    }
    $scmAllows = @($Restrictions.scmIpSecurityRestrictions | Where-Object action -eq 'Allow')
    if ($scmAllows.Count -ne 1 -or $scmAllows[0].name -ne $RuleName -or
        $scmAllows[0].ipAddress -ne $ClientCidr -or $scmAllows[0].priority -ne 100) {
        throw 'SCM must allow exactly the requested single client IPv4 /32 and nothing else.'
    }
}

if ($UploadBackendOnly -and $SkipBackendUpload) {
    throw 'UploadBackendOnly and SkipBackendUpload cannot be combined.'
}
if (-not $SkipBackendUpload) {
    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($BootstrapClientIPv4, [ref] $parsedIp) -or
        $parsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Supply -BootstrapClientIPv4 with your single public egress IPv4 (no CIDR), or use -SkipBackendUpload.'
    }
    $bytes = $parsedIp.GetAddressBytes()
    if ($bytes[0] -in @(0, 10, 127) -or $bytes[0] -ge 224 -or
        ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) {
        throw 'BootstrapClientIPv4 must be the public egress address used by this deployment client.'
    }
    $clientCidr = "$($parsedIp.ToString())/32"
}

$publicRoot = Split-Path $PSScriptRoot -Parent
$infraRoot = Join-Path $publicRoot 'infra'
$backendRoot = Join-Path $publicRoot 'backend'
$workDirectory = Join-Path $infraRoot ".build\$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $workDirectory -Force

try {
    $templatePath = Join-Path $workDirectory 'main.json'
    & az bicep build --file (Join-Path $infraRoot 'main.bicep') --outfile $templatePath `
        --subscription $SubscriptionId --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Bicep build failed; nothing was deployed.' }

    & node --check (Join-Path $backendRoot 'server.js')
    if ($LASTEXITCODE -ne 0) { throw 'Backend syntax check failed; nothing was deployed.' }
    & node --test (Join-Path $backendRoot 'server.test.js') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed; nothing was deployed.' }

    $account = Invoke-AzJson @('account', 'show')
    if ($account.state -ne 'Enabled' -or $account.id -ne $SubscriptionId.ToString()) {
        throw 'The explicitly selected subscription is not enabled or does not match.'
    }
    if ($UploadBackendOnly) {
        $completed = Invoke-AzJson @(
            'deployment', 'group', 'show', '--resource-group', $ResourceGroupName,
            '--name', $DeploymentName, '--query', '{state:properties.provisioningState,outputs:properties.outputs}'
        )
        if ($completed.state -ne 'Succeeded') {
            throw 'UploadBackendOnly requires an already successful infrastructure deployment.'
        }
        $outputs = $completed.outputs
    }
    else {
        foreach ($provider in @('Microsoft.Network', 'Microsoft.Web', 'Microsoft.ApiManagement')) {
            $state = Invoke-AzJson @('provider', 'show', '--namespace', $provider)
            if ($state.registrationState -ne 'Registered') {
                if (-not $RegisterProviders) {
                    throw "$provider is not Registered. Register it explicitly or rerun with -RegisterProviders."
                }
                $null = Invoke-AzJson @('provider', 'register', '--namespace', $provider, '--wait')
                $state = Invoke-AzJson @('provider', 'show', '--namespace', $provider)
                if ($state.registrationState -ne 'Registered') { throw "$provider registration did not complete." }
            }
        }
        $exists = Invoke-AzJson @('group', 'exists', '--name', $ResourceGroupName)
        if (-not $exists) {
            $null = Invoke-AzJson @(
                'group', 'create', '--name', $ResourceGroupName, '--location', 'koreacentral',
                '--tags', 'lab=m365-copilot-private-network', 'data=synthetic-only'
            )
        }
        $outputs = Invoke-AzJson @(
            'deployment', 'group', 'create', '--resource-group', $ResourceGroupName, '--name', $DeploymentName,
            '--template-file', $templatePath, '--mode', 'Incremental',
            '--parameters', "labPrefix=$LabPrefix", "publisherEmail=$PublisherEmail", "publisherName=$PublisherName",
            '--query', 'properties.outputs'
        )
    }
    if (-not $outputs -or -not $outputs.backendName.value) { throw 'Deployment did not return the expected lab outputs.' }
    $appName = $outputs.backendName.value
    $app = Invoke-AzJson @(
        'webapp', 'show', '--resource-group', $ResourceGroupName, '--name', $appName,
        '--query', '{name:name,publicNetworkAccess:publicNetworkAccess}'
    )
    if ($app.publicNetworkAccess -ne 'Disabled') { throw 'Backend was not deployed with publicNetworkAccess Disabled.' }

    if (-not $SkipBackendUpload) {
        $zipPath = Join-Path $workDirectory 'backend.zip'
        Compress-Archive -LiteralPath @(
            (Join-Path $backendRoot 'server.js'),
            (Join-Path $backendRoot 'fixtures.json'),
            (Join-Path $backendRoot 'package.json')
        ) -DestinationPath $zipPath
        $bootstrapRuleName = 'Lab-Client-Bootstrap'
        $restrictionState = Get-AccessRestrictions $appName
        if (@($restrictionState.scmIpSecurityRestrictions | Where-Object name -eq $bootstrapRuleName).Count -ne 0) {
            throw 'A previous bootstrap rule exists. Remove it while public access is Disabled before retrying.'
        }
        if (@($restrictionState.scmIpSecurityRestrictions | Where-Object action -eq 'Allow').Count -ne 0 -or
            @($restrictionState.ipSecurityRestrictions | Where-Object action -eq 'Allow').Count -ne 0) {
            throw 'Refusing to bootstrap a site with existing public Allow rules.'
        }

        try {
            $null = Invoke-AzJson @(
                'webapp', 'config', 'access-restriction', 'set', '--resource-group', $ResourceGroupName,
                '--name', $appName, '--default-action', 'Deny', '--scm-default-action', 'Deny',
                '--use-same-restrictions-for-scm-site', 'false'
            )
            $null = Invoke-AzJson @(
                'webapp', 'config', 'access-restriction', 'add', '--resource-group', $ResourceGroupName,
                '--name', $appName, '--rule-name', $bootstrapRuleName, '--action', 'Allow',
                '--ip-address', $clientCidr, '--priority', '100', '--scm-site', 'true'
            )
            Assert-BootstrapRestrictions (Get-AccessRestrictions $appName) $clientCidr $bootstrapRuleName
            $null = Invoke-AzJson @(
                'webapp', 'update', '--resource-group', $ResourceGroupName, '--name', $appName,
                '--set', 'publicNetworkAccess=Enabled'
            )
            $app = Invoke-AzJson @(
                'webapp', 'show', '--resource-group', $ResourceGroupName, '--name', $appName,
                '--query', '{publicNetworkAccess:publicNetworkAccess}'
            )
            if ($app.publicNetworkAccess -ne 'Enabled') { throw 'The restricted bootstrap endpoint did not become enabled.' }
            Assert-BootstrapRestrictions (Get-AccessRestrictions $appName) $clientCidr $bootstrapRuleName

            # Modern Azure CLI uses Entra authentication with SCM basic publishing auth disabled.
            # The main site remains Deny-all; do not use runtime startup tracking against that public site.
            & az webapp deploy --subscription $SubscriptionId --resource-group $ResourceGroupName `
                --name $appName --src-path $zipPath --type zip --async false --track-status false `
                --enable-kudu-warmup true --restart true --timeout 600000 --only-show-errors --output none
            if ($LASTEXITCODE -ne 0) { throw 'Backend upload failed. Public access is being disabled in finally.' }
        }
        finally {
            # Disable first, including after ambiguous CLI failures, before removing the one-client rule.
            # If this call fails, do not claim safety or success; the operator must close the endpoint.
            $disableFailure = $null
            try {
                $null = Invoke-AzJson @(
                    'webapp', 'update', '--resource-group', $ResourceGroupName, '--name', $appName,
                    '--set', 'publicNetworkAccess=Disabled'
                )
                $app = Invoke-AzJson @(
                    'webapp', 'show', '--resource-group', $ResourceGroupName, '--name', $appName,
                    '--query', '{publicNetworkAccess:publicNetworkAccess}'
                )
                if ($app.publicNetworkAccess -ne 'Disabled') { throw 'publicNetworkAccess did not return to Disabled.' }
            }
            catch {
                $disableFailure = $_
                Write-Warning 'SAFETY CHECK FAILED: verify publicNetworkAccess Disabled immediately. No success is being reported.'
            }
            $restrictionState = Get-AccessRestrictions $appName
            if (@($restrictionState.scmIpSecurityRestrictions | Where-Object name -eq $bootstrapRuleName).Count -gt 0) {
                $null = Invoke-AzJson @(
                    'webapp', 'config', 'access-restriction', 'remove', '--resource-group', $ResourceGroupName,
                    '--name', $appName, '--rule-name', $bootstrapRuleName, '--scm-site', 'true'
                )
            }
            $restrictionState = Get-AccessRestrictions $appName
            if (@($restrictionState.scmIpSecurityRestrictions | Where-Object action -eq 'Allow').Count -ne 0) {
                throw 'SCM bootstrap cleanup failed: an Allow rule remains.'
            }
            if ($disableFailure) { throw $disableFailure }
        }
    }

    $null = & (Join-Path $PSScriptRoot 'Set-BackendAccess.ps1') -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName -DeploymentName $DeploymentName -Access Get
    Write-Host 'Infrastructure checks passed. No APIM subscription key was retrieved or printed.'
    if ($SkipBackendUpload) {
        Write-Warning 'Backend code was not uploaded. End-to-end readiness has not been verified.'
    }
    else {
        Write-Host 'Code upload completed and public access is Disabled. Verify live health through authenticated APIM before collecting evidence.'
    }
    $outputs
}
finally {
    if (Test-Path -LiteralPath $workDirectory) { Remove-Item -LiteralPath $workDirectory -Recurse -Force }
}
