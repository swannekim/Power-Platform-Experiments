#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][uri] $GatewayBaseUrl
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($GatewayBaseUrl.Scheme -ne 'https' -or $GatewayBaseUrl.Query -or $GatewayBaseUrl.Fragment -or $GatewayBaseUrl.UserInfo) {
    throw 'Supply the HTTPS gateway base URL without credentials or query parameters.'
}

$publicRoot = Split-Path $PSScriptRoot -Parent
$agentRoot = Join-Path $publicRoot 'private-api-agent'
$spec = Get-Content (Join-Path $publicRoot 'infra\backend.openapi.json') -Raw | ConvertFrom-Json -AsHashtable
$spec.servers = @(@{ url = '${{GATEWAY_BASE_URL}}' })
foreach ($path in $spec.paths.Values) {
    foreach ($operation in $path.Values) {
        $operation.responses['401'] = @{ description = 'APIM rejected authentication; no backend result.' }
        $operation.responses['403'] = @{ description = 'Access denied; no successful backend result.' }
        $operation.responses['500'] = @{ description = 'Gateway or backend failure; not a successful record read.' }
        $operation.responses['502'] = @{ description = 'Backend connection failed.' }
        $operation.responses['504'] = @{ description = 'Backend connection timed out.' }
    }
}
$spec | ConvertTo-Json -Depth 40 | Set-Content (Join-Path $agentRoot 'appPackage\openapi.json') -Encoding utf8

$envFolder = Join-Path $agentRoot 'env'
$null = New-Item -ItemType Directory -Path $envFolder -Force
$envPath = Join-Path $envFolder '.env.dev'
$envLines = if (Test-Path $envPath) { @(Get-Content $envPath) } else { @() }
$envLines = @($envLines | Where-Object {
    $_ -notmatch '^(GATEWAY_BASE_URL|AGENT_SCOPE|TEAMSFX_ENV|APP_NAME_SUFFIX)='
})
$envLines += @(
    'TEAMSFX_ENV=dev',
    'APP_NAME_SUFFIX=',
    'AGENT_SCOPE=personal',
    "GATEWAY_BASE_URL=$($GatewayBaseUrl.AbsoluteUri.TrimEnd('/'))"
)
$envLines | Set-Content $envPath -Encoding utf8
Write-Host 'Prepared the plugin from the shared OpenAPI contract. The deployment URL is in ignored env\.env.dev only.'
