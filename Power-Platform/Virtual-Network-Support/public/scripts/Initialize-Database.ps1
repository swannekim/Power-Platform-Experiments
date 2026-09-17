[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [Parameter(Mandatory)][string] $ServerName,
    [string] $DatabaseName = 'InventoryDemo',
    [Parameter(Mandatory)][System.Net.IPAddress] $ClientIPv4,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][pscredential] $ReaderCredential
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($ClientIPv4.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'The bootstrap firewall rule requires the caller public IPv4 address.'
}
$readerClientId = [guid]::Parse($ReaderCredential.UserName)

function Invoke-LabAz {
    param([string[]] $Arguments)
    $result = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..1] -join ' ')" }
    if ($result) { $result | ConvertFrom-Json }
}

$server = Invoke-LabAz @('sql', 'server', 'show', '-g', $ResourceGroupName, '-n', $ServerName)
if ($server.publicNetworkAccess -ne 'Disabled') {
    throw 'Start with public network access Disabled; this script will not change a pre-existing public configuration.'
}
$rules = @(Invoke-LabAz @('sql', 'server', 'firewall-rule', 'list', '-g', $ResourceGroupName, '-s', $ServerName))
if ($rules.Count -ne 0) {
    throw 'The lab server must have no existing firewall rules before the narrow bootstrap window.'
}

$ruleName = 'bootstrap-' + [guid]::NewGuid().ToString('N')
$connection = $null
$readerConnection = $null
$ruleCreated = $false
try {
    $null = Invoke-LabAz @(
        'sql', 'server', 'update', '-g', $ResourceGroupName, '-n', $ServerName,
        '--enable-public-network', 'true'
    )
    $null = Invoke-LabAz @(
        'sql', 'server', 'firewall-rule', 'create', '-g', $ResourceGroupName, '-s', $ServerName,
        '-n', $ruleName, '--start-ip-address', "$ClientIPv4", '--end-ip-address', "$ClientIPv4"
    )
    $ruleCreated = $true

    $token = Invoke-LabAz @('account', 'get-access-token', '--resource', 'https://database.windows.net/')
    $connection = [System.Data.SqlClient.SqlConnection]::new(
        "Server=tcp:$ServerName.database.windows.net,1433;Database=$DatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
    )
    $connection.AccessToken = $token.accessToken
    $token = $null
    $connection.Open()
    $sql = Get-Content (Join-Path $PSScriptRoot '..\data\inventory.sql') -Raw
    foreach ($batch in [regex]::Split($sql, '(?m)^\s*GO\s*$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $command = $connection.CreateCommand()
        try {
            $command.CommandText = $batch
            $null = $command.ExecuteNonQuery()
        }
        finally { $command.Dispose() }
    }

    $readerSid = '0x' + [Convert]::ToHexString($readerClientId.ToByteArray())
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = @"
IF USER_ID(N'inventory_reader') IS NULL
    CREATE USER inventory_reader WITH SID = $readerSid, TYPE = E;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'inventory_reader' AND sid <> $readerSid)
    THROW 51000, 'inventory_reader is already mapped to a different Entra principal.', 1;
GRANT SELECT ON OBJECT::dbo.InventoryLive TO inventory_reader;
"@
        $null = $command.ExecuteNonQuery()
    }
    finally { $command.Dispose() }

    $readerConnection = [System.Data.SqlClient.SqlConnection]::new(
        "Server=tcp:$ServerName.database.windows.net,1433;Database=$DatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
    )
    $tokenRequest = @{
        client_id = "$readerClientId"
        client_secret = $ReaderCredential.GetNetworkCredential().Password
        scope = 'https://database.windows.net/.default'
        grant_type = 'client_credentials'
    }
    try {
        $readerToken = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $tokenRequest -ContentType 'application/x-www-form-urlencoded'
        $readerConnection.AccessToken = $readerToken.access_token
        $readerToken = $null
    }
    finally { $tokenRequest.Clear() }
    $readerConnection.Open()
    $command = $readerConnection.CreateCommand()
    try {
        $command.CommandText = @"
SELECT COUNT(*) AS SeedRows,
       HAS_PERMS_BY_NAME('dbo.Inventory', 'OBJECT', 'SELECT') AS CanReadBaseTable,
       HAS_PERMS_BY_NAME('dbo.Inventory', 'OBJECT', 'UPDATE') AS CanUpdateBaseTable
FROM dbo.InventoryLive;
"@
        $reader = $command.ExecuteReader()
        try {
            $null = $reader.Read()
            $rowCount = $reader.GetInt32(0)
            if ($rowCount -ne 6) { throw "Expected 6 synthetic records, found $rowCount." }
            if ((!$reader.IsDBNull(1) -and $reader.GetInt32(1) -ne 0) -or
                (!$reader.IsDBNull(2) -and $reader.GetInt32(2) -ne 0)) {
                throw 'The connector user has unexpected base-table permissions.'
            }
            [pscustomobject]@{
                SeedRows = $rowCount
                Reader = 'inventory_reader'
                ReaderClientId = "$readerClientId"
                ReadableView = 'dbo.InventoryLive'
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
}
finally {
    if ($readerConnection) { $readerConnection.Dispose() }
    if ($connection) { $connection.Dispose() }
    # Azure requires public access enabled to edit firewall rules; always close it afterward.
    try {
        if ($ruleCreated) {
            $null = Invoke-LabAz @(
                'sql', 'server', 'firewall-rule', 'delete', '-g', $ResourceGroupName,
                '-s', $ServerName, '-n', $ruleName
            )
        }
    }
    finally {
        $null = Invoke-LabAz @(
            'sql', 'server', 'update', '-g', $ResourceGroupName, '-n', $ServerName,
            '--enable-public-network', 'false'
        )
        $closed = Invoke-LabAz @('sql', 'server', 'show', '-g', $ResourceGroupName, '-n', $ServerName)
        if ($closed.publicNetworkAccess -ne 'Disabled') {
            throw 'URGENT: bootstrap cleanup did not disable SQL public access.'
        }
    }
}
