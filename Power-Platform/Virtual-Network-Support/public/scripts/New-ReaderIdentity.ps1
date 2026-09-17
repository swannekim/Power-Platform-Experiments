[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][string] $CredentialPath,
    [string] $DisplayName = 'pp-vnet-inventory-reader'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsWindows) { throw 'This script uses Windows DPAPI to protect its local credential file.' }
$credentialFile = [System.IO.Path]::GetFullPath($CredentialPath)
$repositoryPath = & git -C $PSScriptRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw 'Run this script from the lab Git clone so the credential location can be checked.' }
$repositoryRoot = [System.IO.Path]::GetFullPath($repositoryPath.Trim()) + '\'
if ($credentialFile.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Store credentials outside the repository.'
}
if (Test-Path -LiteralPath $credentialFile) { throw 'Credential file already exists; reuse it instead of creating a new identity.' }

function Invoke-IdentityGraph {
    param([string] $Method, [string] $Path, [hashtable] $Body)
    $request = @{
        Method = $Method
        Uri = "https://graph.microsoft.com/v1.0$Path"
        Authentication = 'Bearer'
        Token = $graphToken
        ContentType = 'application/json'
    }
    if ($Body) { $request.Body = $Body | ConvertTo-Json -Depth 8 -Compress }
    Invoke-RestMethod @request
}

$accountJson = & az account show --subscription $SubscriptionId --only-show-errors --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the selected subscription.' }
$account = $accountJson | ConvertFrom-Json
if ($account.tenantId -ne "$TenantId") { throw 'Subscription and requested tenant do not match.' }
$tokenJson = & az account get-access-token --subscription $SubscriptionId --resource-type ms-graph --only-show-errors --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to acquire a Microsoft Graph access token.' }
$graphToken = ConvertTo-SecureString ($tokenJson | ConvertFrom-Json).accessToken -AsPlainText -Force
$tokenJson = $null
$filter = [Uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
$existing = Invoke-IdentityGraph -Method GET -Path "/applications?`$filter=$filter"
if ($existing.value.Count -gt 0) {
    throw "An application named $DisplayName already exists. Inspect and reuse it rather than changing its credentials implicitly."
}

$app = Invoke-IdentityGraph -Method POST -Path '/applications' -Body @{
    displayName = $DisplayName
    signInAudience = 'AzureADMyOrg'
    requiredResourceAccess = @()
}
$principal = Invoke-IdentityGraph -Method POST -Path '/servicePrincipals' -Body @{ appId = $app.appId }
$expires = [DateTime]::UtcNow.AddDays(30).ToString('yyyy-MM-ddTHH:mm:ssZ')
$secret = Invoke-IdentityGraph -Method POST -Path "/applications/$($app.id)/addPassword" -Body @{
    passwordCredential = @{ displayName = 'private-inventory-lab'; endDateTime = $expires }
}
try {
    $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($credentialFile)) -Force
    $secure = ConvertTo-SecureString $secret.secretText -AsPlainText -Force
    [pscredential]::new($app.appId, $secure) | Export-Clixml -LiteralPath $credentialFile
}
finally { $secret = $null }

[pscustomobject]@{
    DisplayName = $DisplayName
    ClientId = $app.appId
    ApplicationObjectId = $app.id
    ServicePrincipalObjectId = $principal.id
    TenantId = "$TenantId"
    SecretExpiresUtc = $expires
    CredentialPath = $credentialFile
}
