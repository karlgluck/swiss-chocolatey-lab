<#
#>
function Update-SwissGuest {
  Param (
    [switch]$Scheduled
  )


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




  
  # Download the latest copy of the host repository




  
  # Copy the SCL module into our PowerShell modules directory

  # Download <repo>/.swiss/packages.config

  # Install packages.config using Chocolatey
  
}
