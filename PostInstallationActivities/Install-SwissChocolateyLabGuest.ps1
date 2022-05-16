<#
  This post-install script is run by AutomatedLab to bootstrap Swiss Chocolatey Lab in the guest VM
#>

# debug sentinel so that we know this script ran
"$(Get-Date)" | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("Desktop")) "LastRanBootstrap.txt")
Get-ChildItem -Path $MyInvocation.MyCommand.Path | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("Desktop")) "Test.txt")


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
#$TempZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($Config.Username)-$($Config.SwissChocolateyLab.Repository)-$([System.IO.Path]::GetRandomFileName()).zip"
$ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"



# Copy the SCL module from our local directory into its new home





# Download <repo>/.swiss/packages.config




# Install Chocolatey
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
shouldInstallChocolatey = $False
try
{
  if (Get-Command "choco")
  {
    Write-Host "Chocolatey is installed"
  }
}
catch {
  $shouldInstallChocolatey = $True
}
finally {
  $ErrorActionPreference = $previousErrorActionPreference
}

if ($shouldInstallChocolatey)
{
  Set-ExecutionPolicy Bypass -Scope Process -Force;
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

choco feature enable -n=allowGlobalConfirmation --no-color | Out-Null
choco feature enable -n=exitOnRebootDetected --no-color | Out-Null
