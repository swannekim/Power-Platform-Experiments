#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [ValidatePattern('^(/health|/(mail|purchase-orders)/[A-Za-z0-9-]{1,64})$')]
    [string] $Path = '/health',
    [ValidatePattern('^[A-Za-z0-9-]{1,100}$')][string] $Nonce = ([guid]::NewGuid().ToString()),
    [Parameter(Mandatory)][string] $RecordPath,
    [ValidateRange(100, 599)][int] $ExpectedStatus = 200,
    [switch] $WithoutKey,
    [switch] $DirectBackend
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$fullPath = [IO.Path]::GetFullPath($RecordPath)
if (Test-Path -LiteralPath $fullPath) {
    throw 'RecordPath already exists. Use a new filename to preserve the earlier observation.'
}
function Invoke-AzJson {
    param([string[]] $Arguments)
    $text = & az @Arguments --subscription $SubscriptionId --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..1] -join ' ')." }
    ($text -join "`n") | ConvertFrom-Json
}

$outputs = Invoke-AzJson @(
    'deployment', 'group', 'show', '--resource-group', $ResourceGroupName,
    '--name', 'm365-copilot-private-network', '--query', 'properties.outputs'
)
if (-not $outputs.gatewayBaseUrl.value -or -not $outputs.backendBaseUrl.value) {
    throw 'Completed lab deployment outputs are required.'
}
$headers = @{ 'Cache-Control' = 'no-cache' }
$baseUrl = $outputs.gatewayBaseUrl.value
if ($DirectBackend) {
    $baseUrl = $outputs.backendBaseUrl.value
}
elseif (-not $WithoutKey) {
    $keyUrl = "$($outputs.apimId.value)/subscriptions/$($outputs.apiSubscriptionName.value)/listSecrets?api-version=2024-05-01"
    $secret = Invoke-AzJson @('rest', '--method', 'post', '--url', $keyUrl)
    $headers['Ocp-Apim-Subscription-Key'] = $secret.primaryKey
    $secret = $null
}
$uri = "$baseUrl$Path`?nonce=$Nonce"
$recordedAt = [DateTime]::UtcNow.ToString('o')
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get `
        -SkipHttpErrorCheck -TimeoutSec 60
}
finally {
    $timer.Stop()
    $headers.Clear()
}
$content = $response.Content
if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
$contentType = [string]($response.Headers['Content-Type'] -join ';')
$body = if ($contentType -match 'application/json') { $content | ConvertFrom-Json } else {
    $content.Substring(0, [Math]::Min(4000, $content.Length))
}
$record = [ordered]@{
    recordedAtUtc = $recordedAt
    origin = 'PowerShell control probe, not an agent invocation'
    endpoint = if ($DirectBackend) { 'direct-backend' } else { 'apim' }
    authentication = if ($DirectBackend -or $WithoutKey) { 'none' } else { 'API-scoped subscription key (not retained)' }
    method = 'GET'
    path = $Path
    nonce = $Nonce
    status = [int]$response.StatusCode
    elapsedSeconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
    body = $body
}
$null = New-Item -ItemType Directory -Path (Split-Path $fullPath -Parent) -Force
$record | ConvertTo-Json -Depth 30 | Set-Content $fullPath -Encoding utf8
if ($response.StatusCode -ne $ExpectedStatus) {
    throw "Expected HTTP $ExpectedStatus; received $($response.StatusCode). Recorded $fullPath."
}
if ($ExpectedStatus -eq 200 -or ($ExpectedStatus -eq 404 -and -not $WithoutKey -and -not $DirectBackend)) {
    if ($body.synthetic -ne $true -or $body.nonce -ne $Nonce -or
        -not $body.observationId -or -not $body.observedAtUtc) {
        throw 'The response did not contain matching synthetic backend observation proof.'
    }
    if ($ExpectedStatus -eq 404 -and $body.error.code -ne 'RecordNotFound') {
        throw 'The 404 was not a backend RecordNotFound result.'
    }
}
[pscustomobject] $record
