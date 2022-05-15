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
