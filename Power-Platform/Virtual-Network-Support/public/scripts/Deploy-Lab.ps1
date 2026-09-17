[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [Parameter(Mandatory)][guid] $EntraAdminObjectId,
    [Parameter(Mandatory)][string] $EntraAdminLogin
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-AzJson {
    param([string[]] $Arguments)
    $result = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..1] -join ' ')" }
    if ($result) { $result | ConvertFrom-Json }
}

$account = Invoke-AzJson @('account', 'show')
if ($account.state -ne 'Enabled') { throw 'The selected subscription is not enabled.' }

foreach ($provider in @('Microsoft.Network', 'Microsoft.Sql', 'Microsoft.PowerPlatform')) {
    $state = Invoke-AzJson @('provider', 'show', '--namespace', $provider)
    if ($state.registrationState -ne 'Registered') {
        throw "Register $provider in the target subscription and wait for Registered before deployment."
    }
}

$null = Invoke-AzJson @(
    'group', 'create', '--name', $ResourceGroupName, '--location', 'westus',
    '--tags', 'lab=powerplatform-vnet-injection', 'purpose=synthetic-demo'
)

Invoke-AzJson @(
    'deployment', 'group', 'create',
    '--resource-group', $ResourceGroupName,
    '--name', 'private-inventory-lab',
    '--template-file', (Join-Path $PSScriptRoot '..\infra\main.bicep'),
    '--parameters', "entraAdminObjectId=$EntraAdminObjectId", "entraAdminLogin=$EntraAdminLogin",
    '--query', 'properties.outputs'
)
