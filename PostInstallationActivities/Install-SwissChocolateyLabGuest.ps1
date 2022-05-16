<#
  This post-install script is run by AutomatedLab to bootstrap Swiss Chocolatey Lab in the guest VM
#>


# Somehow it seems like this is getting run before all the files are copied?
"$(Get-Date)" | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("Desktop")) "LastRanBootstrap.txt")
Get-ChildItem -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("Desktop")) "Test.txt")

# Extract the bootstrap PowerShellModule.zip into our installed modules path (Update-SwissGuest will overwrite this with latest)
$PowerShellModuleZipPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'PowerShellModule.zip'
if (-not (Test-Path $PowerShellModuleZipPath))
{
  Write-Host -ForegroundColor Red "PowerShellModule.zip is missing. It should have been provided by the PostInstallationActivity at $PowerShellModuleZipPath"
  return;
}
Expand-Archive -Path $PowerShellModuleZipPath -DestinationPath ($env:PSModulePath -split ';')[0]
Import-Module SwissChocolateyLab -Force

# debug the module exports
Get-Command -Module "SwissChocolateyLab" | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("Desktop")) "SCLModuleExports.txt")





# Load the guest config file
$GuestConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swissguest"
if (Test-Path $GuestConfigPath)
{
  Write-Host "Loading guest config from $GuestConfigPath"
  $GuestConfig = Get-Content $GuestConfigPath | ConvertFrom-Json
}
else
{
  Write-Host -ForegroundColor Red "No guest configuration found. Try reinstalling the VM? Expected: $GuestConfigPath"
  return
}

# Derived variables
$Headers = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}



# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Global configuration
choco feature enable -n=allowGlobalConfirmation --no-color | Out-Null
choco feature enable -n=exitOnRebootDetected --no-color | Out-Null
