[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $EnvironmentId,
    [Parameter(Mandatory)][string] $PolicyArmId,
    [Parameter(Mandatory)][ValidateSet('Link', 'Unlink')][string] $Action,
    [ValidateRange(60, 3600)][int] $TimeoutSeconds = 2100
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedPrefix = "/subscriptions/$SubscriptionId/resourceGroups/"
if (!$PolicyArmId.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PolicyArmId must belong to the explicitly selected subscription.'
}

$policyJson = & az resource show --subscription $SubscriptionId --ids $PolicyArmId `
    --api-version 2020-10-30-preview --only-show-errors --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the enterprise policy.' }
$policy = $policyJson | ConvertFrom-Json -AsHashtable
if ($policy.kind -ne 'NetworkInjection' -or !$policy.properties.systemId) {
    throw 'The Azure resource is not a provisioned NetworkInjection policy.'
}

$tokenJson = & az account get-access-token --subscription $SubscriptionId `
    --resource 'https://service.powerapps.com/' --only-show-errors --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to acquire a Power Platform access token.' }
$token = ConvertTo-SecureString ($tokenJson | ConvertFrom-Json).accessToken -AsPlainText -Force
$tokenJson = $null
$environmentUrl = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$EnvironmentId`?api-version=2023-06-01&`$expand=properties.enterprisePolicies"

function Read-Environment {
    Invoke-RestMethod -Uri $environmentUrl -Authentication Bearer -Token $token |
        ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
}

function Get-LinkedPolicyId {
    param([hashtable] $Environment)
    $policies = $Environment.properties['enterprisePolicies']
    if ($policies -and $policies['vNets']) { return $policies['vNets']['id'] }
    return $null
}

$environment = Read-Environment
$linkedId = Get-LinkedPolicyId $environment
if ($Action -eq 'Link') {
    if ($environment.properties.governanceConfiguration.protectionLevel -ne 'Standard') {
        throw 'Enable Managed Environments before linking this policy.'
    }
    if ($environment.location -ne $policy.location) {
        throw "Environment geography '$($environment.location)' differs from policy geography '$($policy.location)'."
    }
    if ($linkedId) { throw "Environment already has a VNet policy: $linkedId. No changes made." }
}
elseif ($linkedId -ne $PolicyArmId) {
    throw 'The environment is not linked to the requested policy. No changes made.'
}

if (!$PSCmdlet.ShouldProcess("$EnvironmentId / $PolicyArmId", $Action)) { return }
$requestUrl = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$EnvironmentId/enterprisePolicies/NetworkInjection/$($Action.ToLowerInvariant())?api-version=2019-10-01"
$response = Invoke-WebRequest -Method Post -Uri $requestUrl -Authentication Bearer -Token $token `
    -ContentType 'application/json' -Body (@{ SystemId = $policy.properties.systemId } | ConvertTo-Json)
if ($response.StatusCode -ne 202) { throw "Expected asynchronous acceptance (202), received $($response.StatusCode)." }
if (!$response.Headers.ContainsKey('operation-location')) { throw 'No operation-location was returned; inspect environment History before retrying.' }
$operationUrl = [uri]($response.Headers['operation-location'] | Select-Object -First 1)
if ($operationUrl.Scheme -ne 'https' -or
    !($operationUrl.Host -eq 'api.bap.microsoft.com' -or $operationUrl.Host.EndsWith('.api.bap.microsoft.com'))) {
    throw 'The operation status URL is not an expected Power Platform API endpoint.'
}

Write-Host "$Action accepted. Operation: $operationUrl"
$timer = [Diagnostics.Stopwatch]::StartNew()
$lastState = ''
while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    $operation = Invoke-RestMethod -Uri $operationUrl -Authentication Bearer -Token $token |
        ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
    $state = $operation.state.id
    if ($state -ne $lastState) {
        Write-Host "Enterprise policy operation: $state"
        $lastState = $state
    }
    if ($state -eq 'Succeeded') {
        $after = Read-Environment
        $actualId = Get-LinkedPolicyId $after
        if ($actualId -and $actualId -ne $PolicyArmId) {
            throw 'The environment is associated with a different policy. No additional changes will be made.'
        }
        $associationReady = if ($Action -eq 'Link') {
            $actualId -eq $PolicyArmId -and $after.properties.enterprisePolicies.vNets.linkStatus -eq 'Linked'
        }
        else { !$actualId }
        if (!$associationReady -or $after.properties.states.management.id -ne 'Ready' -or
            $after.properties.states.runtime.id -ne 'Enabled') {
            Start-Sleep -Seconds 15
            continue
        }
        [pscustomobject]@{
            EnvironmentId = "$EnvironmentId"
            Action = $Action
            State = $state
            PolicyArmId = $PolicyArmId
            OperationUrl = "$operationUrl"
            CompletedUtc = [DateTime]::UtcNow.ToString('o')
        }
        return
    }
    if ($state -notin @('NotStarted', 'Running')) {
        throw "Enterprise policy operation ended unexpectedly: $($operation | ConvertTo-Json -Depth 10 -Compress)"
    }
    Start-Sleep -Seconds 15
}
throw "Operation is still pending after $TimeoutSeconds seconds. Check $operationUrl; do not submit a duplicate request."
