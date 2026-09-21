#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ResourceGroupName,
    [ValidateSet('Get', 'Allow', 'Deny')][string] $Access = 'Get',
    [ValidateNotNullOrEmpty()][string] $DeploymentName = 'm365-copilot-private-network',
    [Alias('StatePath', 'EvidencePath')][string] $RecordPath
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

function Assert-Rule {
    param($Rule, [System.Collections.IDictionary] $Expected)
    foreach ($key in $Expected.Keys) {
        if ($Rule.$key -ne $Expected[$key]) {
            throw "Unexpected NSG rule $($Rule.name) field '$key'; refusing to change or attest this network."
        }
    }
}

$outputs = Invoke-AzJson @(
    'deployment', 'group', 'show', '--resource-group', $ResourceGroupName, '--name', $DeploymentName,
    '--query', 'properties.outputs'
)
if (-not $outputs -or -not $outputs.backendAccessRuleName.value) { throw 'Expected lab deployment outputs are missing.' }
$nsgName = $outputs.backendNsgName.value
$ruleName = $outputs.backendAccessRuleName.value
$appName = $outputs.backendName.value
$expectedRule = [ordered]@{
    direction = 'Inbound'
    priority = 100
    protocol = 'Tcp'
    sourceAddressPrefix = $outputs.apimSubnetPrefix.value
    sourcePortRange = '*'
    destinationAddressPrefix = $outputs.backendSubnetPrefix.value
    destinationPortRange = '443'
}

function Get-VerifiedState {
    $app = Invoke-AzJson @(
        'webapp', 'show', '--resource-group', $ResourceGroupName, '--name', $appName,
        '--query', '{id:id,publicNetworkAccess:publicNetworkAccess}'
    )
    if ($app.publicNetworkAccess -ne 'Disabled') {
        throw 'Backend publicNetworkAccess must be Disabled. This script never changes public access or authentication.'
    }
    $subnet = Invoke-AzJson @('network', 'vnet', 'subnet', 'show', '--ids', $outputs.backendSubnetId.value)
    if ($subnet.networkSecurityGroup.id -ne $outputs.backendNsgId.value -or
        $subnet.privateEndpointNetworkPolicies -notin @('Enabled', 'NetworkSecurityGroupEnabled')) {
        throw 'The private-endpoint subnet must use the expected NSG with private-endpoint NSG policies enabled.'
    }
    $nsg = Invoke-AzJson @('network', 'nsg', 'show', '--resource-group', $ResourceGroupName, '--name', $nsgName)
    $denyRules = @($nsg.securityRules | Where-Object name -eq 'Deny-Other-Inbound')
    if ($denyRules.Count -ne 1) { throw 'The explicit deny-other-inbound rule is missing.' }
    Assert-Rule $denyRules[0] ([ordered]@{
        access = 'Deny'; direction = 'Inbound'; priority = 200; protocol = '*'
        sourceAddressPrefix = '*'; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = '*'
    })
    $unexpectedRules = @($nsg.securityRules | Where-Object {
        $_.direction -eq 'Inbound' -and $_.priority -le 200 -and
        $_.name -notin @($ruleName, 'Deny-Other-Inbound')
    })
    if ($unexpectedRules.Count -gt 0) { throw 'Unexpected higher-priority inbound rules could invalidate the experiment.' }
    $rule = Invoke-AzJson @(
        'network', 'nsg', 'rule', 'show', '--resource-group', $ResourceGroupName,
        '--nsg-name', $nsgName, '--name', $ruleName
    )
    Assert-Rule $rule $expectedRule
    if ($rule.access -notin @('Allow', 'Deny')) { throw 'The toggle rule has an unexpected access state.' }
    [pscustomobject]@{ App = $app; Subnet = $subnet; Rule = $rule; Nsg = $nsg }
}

$before = Get-VerifiedState
if ($Access -ne 'Get' -and $before.Rule.access -ne $Access) {
    # The only mutation is this existing rule's access field. Never alter auth, DNS, routes, or API data.
    $null = Invoke-AzJson @(
        'network', 'nsg', 'rule', 'update', '--resource-group', $ResourceGroupName,
        '--nsg-name', $nsgName, '--name', $ruleName, '--access', $Access
    )
}
$after = Get-VerifiedState
if ($Access -ne 'Get' -and $after.Rule.access -ne $Access) { throw 'The NSG rule did not reach the requested state.' }

$record = [ordered]@{
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    subscriptionId = $SubscriptionId.ToString()
    resourceGroupName = $ResourceGroupName
    requestedAccess = $Access
    previousAccess = $before.Rule.access
    access = $after.Rule.access
    backendPublicNetworkAccess = $after.App.publicNetworkAccess
    privateEndpointNetworkPolicies = $after.Subnet.privateEndpointNetworkPolicies
    flushConnection = ($after.Nsg.PSObject.Properties['flushConnection'] | Select-Object -ExpandProperty Value)
    backendSubnetId = $outputs.backendSubnetId.value
    nsgId = $outputs.backendNsgId.value
    ruleName = $ruleName
    rule = $expectedRule
    controlPlaneVerified = $true
    dataPlaneVerified = $false
    note = 'NSGs are stateful. Allow propagation time and use fresh backend TCP connections. A control-plane rule state alone does not prove a data-plane failure or recovery.'
}
if ($RecordPath) {
    $fullPath = [IO.Path]::GetFullPath($RecordPath)
    $null = New-Item -ItemType Directory -Path (Split-Path $fullPath -Parent) -Force
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fullPath -Encoding utf8
}
[pscustomobject] $record
