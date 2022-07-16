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


# Create a network shared folder that the host can access at \\THISMACHINE\Shared
New-Item "Shared" -ItemType Directory
New-SMBShare -Name "Shared" -Path "C:\Shared"


# Set up Chocolatey
Install-Chocolatey


# Run the first self-update
Update-SwissGuest -FirstTime
