<#
.SYNOPSIS
  Runs one SQL file (a single batch - no GO splitting) against an Azure SQL database with an Entra token and prints
  every result set, messages and SQL errors.

.DESCRIPTION
  Take the values from the project config: -Server / -Database = databases.<env> (pp-project.yaml),
  -Tenant = environments.<env>.tenant_id, -CachePath = tools.sql_token_cache (pp-project.local.yaml).
  Read-only by default is a rule of the pp-sql skill, not of this script: it runs whatever the file contains.

.EXAMPLE
  & "<pp-sql skill folder>\scripts\Invoke-Sql.ps1" -Server <server>.database.windows.net -Database <database> `
    -Tenant <tenant-id> -CachePath <tools.sql_token_cache> -SqlFile .\query.sql
#>
param(
  [Parameter(Mandatory)][string]$Server,
  [Parameter(Mandatory)][string]$Database,
  [Parameter(Mandatory)][string]$SqlFile,
  [Parameter(Mandatory)][string]$Tenant,
  [Parameter(Mandatory)][string]$CachePath,
  [string]$SaveFirstStringTo
)
$tok = & (Join-Path $PSScriptRoot 'Get-SqlToken.ps1') -Tenant $Tenant -CachePath $CachePath
$cn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$Server,1433;Database=$Database;Encrypt=True;Connection Timeout=20")
$cn.AccessToken = $tok; $cn.Open()
$cmd = $cn.CreateCommand(); $cmd.CommandTimeout = 120
$cmd.CommandText = [IO.File]::ReadAllText($SqlFile)
$cn.add_InfoMessage({ param($s,$e) Write-Output ("MSG: " + $e.Message) })
$cmd.Connection.FireInfoMessageEventOnUserErrors = $false
try { $r = $cmd.ExecuteReader() } catch { Write-Output ("SQL ERROR: " + $_.Exception.InnerException.Message); $cn.Close(); exit 0 }
$n = 0; $saved = $null
do {
  $n++
  if ($r.FieldCount -eq 0) { continue }
  $cols=@(); for($i=0;$i -lt $r.FieldCount;$i++){$cols+=$r.GetName($i)}
  Write-Output ("=== set $n : " + ($cols -join ' | '))
  while($r.Read()){
    if ($SaveFirstStringTo -and $n -eq 1) { $saved += $r.GetString(0); continue }   # long FOR JSON output arrives as several rows: join them as they are
    $v=@(); for($i=0;$i -lt $r.FieldCount;$i++){ $v += $(if($r.IsDBNull($i)){'NULL'}else{[string]$r[$i]}) }; Write-Output ($v -join ' | ')
  }
} while ($r.NextResult())
if ($null -ne $saved) { [IO.File]::WriteAllText($SaveFirstStringTo, $saved); Write-Output "saved -> $SaveFirstStringTo" }
$cn.Close()
