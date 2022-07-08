<#
#>
function Update-SwissGuest {
  Param (
    [switch]$Scheduled,
    [switch]$FirstTime,
    [switch]$SkipModuleUpdate,
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


  # Make sure that Update-SwissGuest gets called when this user logs in
  # TODO: This is a copy-paste from Update-SwissHost.ps1, can we combine them?
  if (-not $Scheduled)
  {
    $accountId = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $AutoUpdateTrigger = New-JobTrigger -AtLogOn
    $JobOptions = New-ScheduledJobOption -StartIfOnBattery -RunElevated
    $Task = Get-ScheduledJob -Name $GuestConfig.AutoUpdateJobName -ErrorAction SilentlyContinue
    if ($null -ne $Task)
    {
      Unregister-ScheduledJob $Task -Confirm:$False
    }
    if ($GuestConfig.AutoUpdateEnabled)
    {
      Write-Host "Registering startup job to run Update-SwissHost: $($GuestConfig.AutoUpdateJobName)"
      Register-ScheduledJob -Name $GuestConfig.AutoUpdateJobName -Trigger $AutoUpdateTrigger -ScheduledJobOption $JobOptions -ScriptBlock { Import-Module "SwissChocolateyLab" ; Update-SwissGuest -Scheduled } | Out-Null
      $TaskPrincipal = New-ScheduledTaskPrincipal -UserID $accountId -LogonType Interactive -RunLevel Highest
      Set-ScheduledTask -TaskPath '\Microsoft\Windows\PowerShell\ScheduledJobs' -TaskName $GuestConfig.AutoUpdateJobName -Principal $TaskPrincipal | Out-Null
    }
  }
  elseif (-not $GuestConfig.AutoUpdateEnabled)
  {
    # If the config disables auto-update but we're currently running an auto-update, use another task to unschedule this in the future
    $RemoveScheduledJobName = "Remove$($GuestConfig.AutoUpdateJobName)"
    Write-Host "Removing startup job using a helper: $RemoveScheduledJobName"
    $RemoveScheduledJobTrigger = New-JobTrigger -Once -At (get-date).AddSeconds(10)
    $JobOptions = New-ScheduledJobOption -StartIfOnBattery -RunElevated
    $Script = @"
      `$Task = Get-ScheduledJob -Name '$($GuestConfig.AutoUpdateJobName)' -ErrorAction SilentlyContinue
      if (`$null -ne `$Task)
      {
        Unregister-ScheduledJob `$Task -Confirm:`$False
      }
      Unregister-ScheduledJob '$RemoveScheduledJobName' -Confirm:`$False
"@
    Register-ScheduledJob -Name $RemoveScheduledJobName -Trigger $RemoveScheduledJobTrigger -ScheduledJobOption $JobOptions -ScriptBlock ([scriptblock]::Create($Script))
    
    # this script must not be running when the removal task executes
    return
  }



  # Derived variables
  $GuestHeaders = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}
  $ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"
  $PackagesConfigUrl = "$($GuestConfig.ApiContentsUrl)/.swiss/packages.config"
  $PackagesConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "packages.config"

  if (-not $SkipModuleUpdate)
  {
    # Download the latest copy of the host repository
    $TempRepositoryZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($GuestConfig.HostConfig.UserName)-$($GuestConfig.HostConfig.Repository)-$([System.IO.Path]::GetRandomFileName()).zip"
    try
    {
      Write-Host "Downloading latest '$($GuestConfig.HostConfig.Repository)' branch $($GuestConfig.HostConfig.Branch) -> $TempRepositoryZipPath"
      Invoke-WebRequest -Headers $SwissHeaders -Uri $GuestConfig.HostConfig.ZipUrl -OutFile $TempRepositoryZipPath
      $ZipFileHash = (Get-FileHash $TempRepositoryZipPath -Algorithm SHA256).Hash
      Write-Host " > Downloaded, SHA256 = $ZipFileHash"
    }
    catch
    {
      Write-Host -ForegroundColor Red "Unable to download host repository ZIP file from $($GuestConfig.HostConfig.ZipUrl)"
      return
    }
    
    # Extract the SCL module into our PowerShell modules directory, clobbering anything that's there
    # Install /Module/** as a PowerShell module
    # https://community.idera.com/database-tools/powershell/powertips/b/tips/posts/extract-specific-files-from-zip-archive
    Write-Host "Install $($GuestConfig.HostConfig.Repository)/Module/** as a PowerShell module into $ModulesFolder"
    if (Test-Path $ModulesFolder) { Remove-Item -Recurse -Force $ModulesFolder }
    Expand-ZipFileDirectory -ZipFilePath $TempRepositoryZipPath -DirectoryInZipFile "Module" -OutputPath $ModulesFolder

    # Re-run the update with the newer version
    Import-Module SwissChocolateyLab -Force
    Update-SwissGuest -SkipModuleUpdate -Scheduled $Scheduled -FirstTime $FirstTime
    return
  }

  # Update the version of chocolatey
  if (-not $FirstTime)
  {
    Install-Chocolatey
  }

  # Download <repo>/.swiss/packages.config
  Write-Host "Installing packages.config..."
    Invoke-WebRequest -Method Get -Uri $PackagesConfigUrl -Headers $GuestHeaders -OutFile $PackagesConfigPath
  try
  {
    Invoke-WebRequest -Method Get -Uri $PackagesConfigUrl -Headers $GuestHeaders -OutFile $PackagesConfigPath
    Write-Host " > Installing choco packages from $PackagesConfigUrl"
  }
  catch
  {
    Write-Host -ForegroundColor Yellow " > No packages.config found at $PackagesConfigUrl"
  }

  # Install packages.config using Chocolatey
  if (Test-Path $PackagesConfigPath)
  {
    $Result = Install-ChocolateyPackageConfig -Path $PackagesConfigPath
    if ($Result.PackagesNotInstalled.Count -gt 0)
    {
      Write-Host -ForegroundColor Red (" > Packages couldn't be installed: " + ($Result.PackagesNotInstalled -join ", "))
    }
    if ($Result.RestartRequired)
    {
      if ($Scheduled)
      {
        # wait a minute if a scheduled operation wants to restart the computer so that we don't end up in an accidental reboot loop
        Wait-Event -Time 60
      }
      if ($GuestConfig.AutoUpdateEnabled -or $FirstTime)
      {
        Restart-Computer
      }
      else
      {
        Write-Host -ForegroundColor Red " > Installing packages requires a reboot"
      }
    }
    if ($Result.Finished)
    {
      Write-Host " > Finished installing packages."
    }
  }
  else
  {
      Write-Host -ForegroundColor Yellow @"
 > Missing Chocolatey configuration. No packages will be installed. Expecting either:
    1. $PackagesConfigUrl
    2. $PackagesConfigPath
"@
  }

  Write-Host "SwissChocolateyLab (Guest) is now ready. Commands:"
  (Get-Command -Module "SwissChocolateyLab" | Where-Object { $_.CommandType -eq 'Function' } | ForEach-Object { " * $($_.Name)" })



}






