param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/HR',
    [string]$ListName = 'Employees'
)
# Builds EmployeeCommentEditor_Solution.zip (importable in make.powerapps.com > Solutions > Import).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = $PSScriptRoot
$src = Join-Path $root 'src'
$out = Join-Path $root 'out'
$appName = 'new_employeecommenteditor_8a3f1'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item $out, "$out\sol\CanvasApps" -ItemType Directory -Force | Out-Null

# SharePoint site/list into the app sources
foreach ($f in 'Connections\Connections.json', 'DataSources\Employees.json') {
    $p = Join-Path $src $f
    (Get-Content $p -Raw) -replace 'https://[^"]+\.sharepoint\.com/[^"]*', $SiteUrl | Set-Content $p -Encoding utf8
}

# Table definition (schema of the list)
function Prop($title, $type, $perm, $fns) {
    $o = [ordered]@{ title = $title; type = $type; 'x-ms-permission' = $perm; 'x-ms-sort' = 'asc,desc'
        'x-ms-capabilities' = [ordered]@{ filterFunctions = $fns } }
    if ($type -eq 'string') { $o.maxLength = 255 }
    $o
}
$props = [ordered]@{
    ID = [ordered]@{ title = 'ID'; type = 'integer'; format = 'int64'; 'x-ms-keyType' = 'primary'; 'x-ms-keyOrder' = 1
        'x-ms-permission' = 'read-only'; 'x-ms-sort' = 'asc,desc'; 'x-ms-capabilities' = [ordered]@{ filterFunctions = @('eq') } }
    Title = Prop 'Title' 'string' 'read-write' @('eq', 'startswith')
    Full_x0020_Name = Prop 'Full Name' 'string' 'read-write' @('eq', 'startswith')
    comment = Prop 'comment' 'string' 'read-write' @('eq', 'startswith')
}
$entity = [ordered]@{
    name = $ListName; title = $ListName; 'x-ms-permission' = 'read-write'
    'x-ms-capabilities' = [ordered]@{
        sortRestrictions   = [ordered]@{ sortable = $true; unsortableProperties = @() }
        filterRestrictions = [ordered]@{ filterable = $true; nonFilterableProperties = @() }
        isOnlyServerPagable = $true
        filterFunctionSupport = @('and', 'or', 'eq', 'startswith', 'gt', 'ge', 'lt', 'le', 'ne')
        serverPagingOptions = @('top', 'skiptoken'); odataVersion = 3
    }
    schema = [ordered]@{ type = 'array'; items = [ordered]@{ type = 'object'; required = @(); properties = $props } }
}
$td = [ordered]@{ DataEntityMetadataJson = [ordered]@{ $ListName = ($entity | ConvertTo-Json -Depth 20 -Compress) }; EntityName = 'Employees'; TableName = $ListName }
New-Item "$src\pkgs\TableDefinitions" -ItemType Directory -Force | Out-Null
$td | ConvertTo-Json -Depth 5 | Set-Content "$src\pkgs\TableDefinitions\Employees.json" -Encoding utf8

# Pack msapp
pac canvas pack --sources $src --msapp "$out\app.msapp" --overwrite
if ($LASTEXITCODE -ne 0) { throw 'pac canvas pack failed' }
Copy-Item "$out\app.msapp" "$out\sol\CanvasApps\${appName}_DocumentUri.msapp"

# Solution files
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$conn = '{"shared_sharepointonline":{"id":"/providers/Microsoft.PowerApps/apis/shared_sharepointonline","displayName":"SharePoint","dataSources":["Employees"],"dependencies":[],"dependents":[],"parameterHints":{}}}'
$files = @{
    '[Content_Types].xml'                  = '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/octet-stream" /><Default Extension="msapp" ContentType="application/octet-stream" /></Types>'
    'solution.xml'                         = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml version="9.2.0.0" SolutionPackageVersion="9.2" languagecode="1033" generatedBy="CrmLive" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <SolutionManifest>
    <UniqueName>EmployeeCommentEditor</UniqueName>
    <LocalizedNames><LocalizedName description="Employee Comment Editor" languagecode="1033" /></LocalizedNames>
    <Descriptions />
    <Version>1.0.0.0</Version>
    <Managed>0</Managed>
    <Publisher>
      <UniqueName>employeecommentpub</UniqueName>
      <LocalizedNames><LocalizedName description="Employee Comment Publisher" languagecode="1033" /></LocalizedNames>
      <Descriptions />
      <EMailAddress xsi:nil="true" /><SupportingWebsiteUrl xsi:nil="true" />
      <CustomizationPrefix>new</CustomizationPrefix>
      <CustomizationOptionValuePrefix>10000</CustomizationOptionValuePrefix>
      <Addresses />
    </Publisher>
    <RootComponents><RootComponent type="300" schemaName="$appName" behavior="0" /></RootComponents>
    <MissingDependencies />
  </SolutionManifest>
</ImportExportXml>
"@
    'customizations.xml'                   = '<?xml version="1.0" encoding="utf-8"?><ImportExportXml xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Entities></Entities><Roles></Roles><Workflows></Workflows><FieldSecurityProfiles></FieldSecurityProfiles><Templates /><EntityMaps /><EntityRelationships /><OrganizationSettings /><optionsets /><CustomControls /><EntityDataProviders /><Languages><Language>1033</Language></Languages></ImportExportXml>'
    "CanvasApps\$appName.meta.xml"              = @"
<?xml version="1.0" encoding="utf-8"?>
<CanvasApp>
  <Name>$appName</Name>
  <AppVersion>$ts</AppVersion>
  <Status>Ready</Status>
  <CreatedByClientVersion>3.26091.1</CreatedByClientVersion>
  <MinClientVersion>3.26091.1</MinClientVersion>
  <Tags>{}</Tags>
  <IsCustomizable>1</IsCustomizable>
  <BackgroundColor>rgba(0, 176, 240, 1)</BackgroundColor>
  <DisplayName>Employee Comment Editor</DisplayName>
  <Description>Search an Employees SharePoint list (200k items) and update an item's comment.</Description>
  <CanvasAppType>0</CanvasAppType>
  <AuthorizationReferences>[{"id":"/providers/Microsoft.PowerApps/apis/shared_sharepointonline"}]</AuthorizationReferences>
  <ConnectionReferences>$conn</ConnectionReferences>
  <DatabaseReferences>{}</DatabaseReferences>
  <AppComponents />
  <AppDocumentUri>/CanvasApps/${appName}_DocumentUri.msapp</AppDocumentUri>
</CanvasApp>
"@
}
foreach ($k in $files.Keys) {
    $p = Join-Path "$out\sol" $k
    [IO.File]::WriteAllText($p, $files[$k], $utf8)
}

# Zip with forward-slash entry names
$zip = Join-Path $root 'EmployeeCommentEditor_Solution.zip'
Remove-Item $zip -Force -ErrorAction SilentlyContinue
$za = [IO.Compression.ZipFile]::Open($zip, 'Create')
foreach ($f in Get-ChildItem "$out\sol" -Recurse -File) {
    $rel = $f.FullName.Substring("$out\sol\".Length).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $rel)
}
$za.Dispose()
Write-Host "Created $zip"

