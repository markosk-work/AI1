param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [int]$Count = 200000
)
# Requires: Install-Module PnP.PowerShell
Connect-PnPOnline -Url $SiteUrl -Interactive
New-PnPList -Title 'Employees' -Template GenericList -OnQuickLaunch | Out-Null
Add-PnPField -List 'Employees' -DisplayName 'Full Name' -InternalName 'Full_x0020_Name' -Type Text -AddToDefaultView | Out-Null
Add-PnPField -List 'Employees' -DisplayName 'comment' -InternalName 'comment' -Type Note -AddToDefaultView | Out-Null
# Index + unique + required BEFORE loading data (a list over 5000 items cannot be indexed afterwards)
Set-PnPField -List 'Employees' -Identity 'Full_x0020_Name' -Values @{ Indexed = $true; EnforceUniqueValues = $true; Required = $true }

$batch = New-PnPBatch
for ($i = 1; $i -le $Count; $i++) {
    $name = 'Employee {0:D6}' -f $i
    Add-PnPListItem -List 'Employees' -Values @{ Title = $name; Full_x0020_Name = $name } -Batch $batch
    if ($i % 500 -eq 0) { Invoke-PnPBatch $batch; $batch = New-PnPBatch; Write-Host "$i / $Count" }
}
Invoke-PnPBatch $batch
