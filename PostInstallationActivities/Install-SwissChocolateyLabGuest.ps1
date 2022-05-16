<#
  This post-install script is run by AutomatedLab to bootstrap Swiss Chocolatey Lab in the guest VM
#>

# Extract the bootstrap PowerShellModule.zip into our installed modules path (Update-SwissGuest will overwrite this with latest)
$PowerShellModuleZipPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'PowerShellModule.zip'
if (-not (Test-Path $PowerShellModuleZipPath))
{
  Write-Host -ForegroundColor Red "PowerShellModule.zip is missing. It should have been provided by the PostInstallationActivity at $PowerShellModuleZipPath"
  return;
}
Expand-Archive -Path $PowerShellModuleZipPath -DestinationPath ($env:PSModulePath -split ';')[0]
Import-Module SwissChocolateyLab -Force







# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Global configuration
choco feature enable -n=allowGlobalConfirmation --no-color | Out-Null
choco feature enable -n=exitOnRebootDetected --no-color | Out-Null



# Run the first self-update
Update-SwissGuest