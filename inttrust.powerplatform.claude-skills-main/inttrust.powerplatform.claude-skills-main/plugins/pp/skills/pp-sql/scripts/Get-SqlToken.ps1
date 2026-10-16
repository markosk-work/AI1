<#
.SYNOPSIS
  Returns an Entra access token (Azure SQL by default) for the signed-in person, without an interactive sign-in.

.DESCRIPTION
  - First use: -Register runs a device-code sign-in (prints the code; the person enters it at https://microsoft.com/devicelogin)
    and stores the refresh token DPAPI-encrypted (current Windows user only) at -CachePath.
  - Afterwards: the refresh token is exchanged silently at the Entra v2 token endpoint (Azure CLI public client) and the
    rotated refresh token is written back.
  - -Scope requests a token for another resource with the same sign-in (for example a Dataverse org
    'https://<org>.crm4.dynamics.com//.default' for read-only diagnostics); the cache is then left untouched.

  Take the values from the project config: -Tenant = environments.<env>.tenant_id (pp-project.yaml),
  -CachePath = tools.sql_token_cache (pp-project.local.yaml). The token is returned to the caller; never print it.

.EXAMPLE
  $cn = New-Object System.Data.SqlClient.SqlConnection('Server=tcp:<server>,1433;Database=<db>;Encrypt=True')
  $cn.AccessToken = & "<pp-sql skill folder>\scripts\Get-SqlToken.ps1" -Tenant <tenant-id> -CachePath "$env:LOCALAPPDATA\<Project>\db-refresh.dpapi"
  $cn.Open()
#>
param(
  [Parameter(Mandatory)][string]$Tenant,
  [Parameter(Mandatory)][string]$CachePath,
  [string]$Scope = 'https://database.windows.net//.default offline_access openid profile',
  [switch]$Register,
  [switch]$Print,
  [switch]$NoAz      # accepted for compatibility with older commands; no effect
)
$ErrorActionPreference = 'Stop'
$Client = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'   # Azure CLI public client (device code allowed)
$CachePath = [Environment]::ExpandEnvironmentVariables($CachePath)
$Dir = Split-Path -Parent $CachePath
$TokenUrl = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"
$KeepCache = -not $PSBoundParameters.ContainsKey('Scope')

function Save-Refresh([string]$rt) {
  if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
  $sec = ConvertTo-SecureString $rt -AsPlainText -Force
  Set-Content -Path $CachePath -Value (ConvertFrom-SecureString $sec) -Encoding ascii   # DPAPI, current user + machine
}
function Load-Refresh {
  if (-not (Test-Path $CachePath)) { return $null }
  $sec = ConvertTo-SecureString (Get-Content $CachePath -Raw).Trim()
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
function Identity([string]$jwt) {
  $p = $jwt.Split('.')[1].Replace('-', '+').Replace('_', '/'); switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  '{0} (expires {1:HH:mm})' -f $c.upn, [DateTimeOffset]::FromUnixTimeSeconds([int64]$c.exp).ToLocalTime()
}

$token = $null
if ($Register) {
  $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/devicecode" -Body @{ client_id = $Client; scope = $Scope } -ContentType 'application/x-www-form-urlencoded'
  Write-Host ("Sign in at {0} with code {1} (valid {2} min)" -f $r.verification_uri, $r.user_code, [int]($r.expires_in / 60))
  $deadline = (Get-Date).AddSeconds([int]$r.expires_in)
  while (-not $token -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds ([Math]::Max(5, [int]$r.interval))
    try { $t = Invoke-RestMethod -Method Post -Uri $TokenUrl -Body @{ grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $Client; device_code = $r.device_code } -ContentType 'application/x-www-form-urlencoded'; $token = $t.access_token; if ($t.refresh_token) { Save-Refresh $t.refresh_token } }
    catch { $m = ''; if ($_.ErrorDetails) { $m = $_.ErrorDetails.Message }; if ($m -notmatch 'authorization_pending' -and $m -notmatch 'slow_down') { throw ('device code error: ' + $m) } }
  }
  if (-not $token) { throw 'device code expired without sign-in' }
  Write-Host ('Registered: ' + (Identity $token) + '; refresh token stored DPAPI-encrypted at ' + $CachePath)
}
else {
  $rt = Load-Refresh
  if (-not $rt) { throw "No saved login at $CachePath. Run once with -Register (device code) to store a refresh token." }
  $t = Invoke-RestMethod -Method Post -Uri $TokenUrl -Body @{ grant_type = 'refresh_token'; client_id = $Client; refresh_token = $rt; scope = $Scope } -ContentType 'application/x-www-form-urlencoded'
  $token = $t.access_token
  if ($t.refresh_token -and $KeepCache) { Save-Refresh $t.refresh_token }
}
if ($Print) { $token } else { return $token }
