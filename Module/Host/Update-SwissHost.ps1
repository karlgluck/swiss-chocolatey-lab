<#
.DESCRIPTION
  Configures the host to install Swiss-VM's
.INPUTS
.OUTPUTS
.NOTES
  Can be called in 3 ways: first-time bootstrapping, every time the host restarts, or manually.
#>
function Update-SwissHost {
  [CmdletBinding()]
  Param (
    [PSCustomObject]$Bootstrap,
    [Switch]$Scheduled
  )



  # Initialize the config with whatever already exists
  $ConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swisshost"
  if (Test-Path $ConfigPath)
  {
    Write-Host "Loading host config from $ConfigPath"
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
  }
  else
  {
    Write-Host "No existing host configuration found at $ConfigPath"
    $Config = [PSCustomObject]@{}
  }

  # Get the repository's configuration file
  if ($null -ne $Bootstrap)
  {
    Write-Host "Bootstrapping '${env:ComputerName}'"

    # Save the access token
    Add-Member -Name 'Token' -Value $Bootstrap.Token -Force -InputObject $Config -MemberType NoteProperty

    # Parse repository configuration from the URL
    $Match = [RegEx]::Match($Bootstrap.Url, 'githubusercontent\.com\/([^\/]+)\/([^\/]+)\/(\S+)\/Module\/Host\/Update-SwissHost.ps1')
    if ($Match.Success)
    {
      Add-Member -Name 'UserName' -Value $Match.Groups[1].Value -Force -InputObject $Config -MemberType NoteProperty
      Add-Member -Name 'Repository' -Value $Match.Groups[2].Value -Force -InputObject $Config -MemberType NoteProperty
      Add-Member -Name 'Branch' -Value $Match.Groups[3].Value -Force -InputObject $Config -MemberType NoteProperty
      Add-Member -Name 'RawUrl' -Value "https://raw.githubusercontent.com/$($Config.UserName)/$($Config.Repository)/$($Config.Branch)" -Force -InputObject $Config -MemberType NoteProperty
      Add-Member -Name 'ZipUrl' -Value "https://github.com/$($Config.UserName)/$($Config.Repository)/archive/refs/heads/$($Config.Branch).zip" -Force -InputObject $Config -MemberType NoteProperty
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> Bootstrapping URL doesn't match expected format (see README.md) <<<<"
      return
    }

    # Prevent accidental use of the Bootstrap variable later in the script
    Remove-Variable -Name 'Bootstrap'
  }
  else
  {
    # Expect a config file to exist, otherwise we can't know what to do
    if (-not (Test-Path $ConfigPath))
    {
      Write-Host -ForegroundColor Red ">>>> FATAL: Missing config file. Try bootstrapping again? (see README.md) <<<<"
      Write-Host -ForegroundColor Red "Expected: $ConfigPath"
      return
    }
  }






  # Now that we have the config, define derived variables
  $GenericConfigUrl = "$($Config.RawUrl)/Config/.swisshost"
  $HostSpecificConfigUrl = "$($Config.RawUrl)/Config/${env:ComputerName}.swisshost"
  $Headers = @{Authorization=@('token ',$Config.Token) -join ''; 'Cache-Control'='no-store'}
  $TempRepositoryZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($Config.UserName)-$($Config.Repository)-$([System.IO.Path]::GetRandomFileName()).zip"
  $ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"





  # Require Administrator privileges
  if (-not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
  {
    Write-Host -ForegroundColor Red ">>>> Must run in an Administrator PowerShell terminal (open with Win+X, A) <<<<"
    return
  }
  
  # Always allow scripts to run on this system and set the TLS security protocol
  Set-ExecutionPolicy Bypass -Scope LocalMachine -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

  # Grab the configuration from the repository and merge it into $Config
  $RemoteConfig = [PSCustomObject]@{}
  try
  {
    $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $HostSpecificConfigUrl -Headers $Headers).Content | ConvertFrom-Json
    Write-Host "Using host-specific config: $HostSpecificConfigUrl"
  }
  catch
  {
    try
    {
      $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $GenericConfigUrl -Headers $Headers).Content | ConvertFrom-Json
      Write-Host "Using generic host config: $GenericConfigUrl"
    }
    catch
    {
      Write-Host -ForegroundColor Red ">>>> Missing both default and host-specific config files in repository <<<<"
      Write-Host -ForegroundColor Red "Expected either:"
      Write-Host -ForegroundColor Red " * $GenericConfigUrl"
      Write-Host -ForegroundColor Red " * $HostSpecificConfigUrl"
      return;
    }
  }
  finally
  {
    if (Test-Path 'variable:RemoteConfig')
    {
      # Move properties into Config
      $RemoteConfig.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" } | ForEach-Object { Add-Member -Name $_.Name -Value $_.Value -Force -InputObject $Config -MemberType NoteProperty }
      Remove-Variable -Name RemoteConfig
    }
  }

  # Write the host configuration file
  ConvertTo-Json $Config | Out-File -FilePath $ConfigPath

  Write-Host -ForegroundColor Blue "AutoUpdateEnabled = $($Config.AutoUpdateEnabled)"


  # Download the entire repository
  try
  {
    Write-Host "Downloading latest '$($Config.Repository)' branch $($Config.Branch) -> $TempRepositoryZipPath"
    Invoke-WebRequest -Headers $SwissHeaders -Uri $Config.ZipUrl -OutFile $TempRepositoryZipPath
    $ZipFileHash = (Get-FileHash $TempRepositoryZipPath -Algorithm SHA256).Hash
    Write-Host " > Downloaded, SHA256 = $ZipFileHash"
  }
  catch
  {
    Write-Host -ForegroundColor Red "Unable to download repository ZIP file from $($Config.ZipUrl)"
    return
  }




  # Install /Module/** as a PowerShell module
  # https://community.idera.com/database-tools/powershell/powertips/b/tips/posts/extract-specific-files-from-zip-archive
  Write-Host "Install <repo>/Module/** as a PowerShell module into $ModulesFolder"
  if (Test-Path $ModulesFolder) { Remove-Item -Recurse -Force $ModulesFolder }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $Zip = [System.IO.Compression.ZipFile]::OpenRead($TempRepositoryZipPath)
  $Zip.Entries | 
    Where-Object { $_.Name -ne "" } |
    ForEach-Object {
      $Match = [RegEx]::Match($_.FullName, "\/Module\/(.*)")
      if ($Match.Success)
      {
        $FilePath = Join-Path $ModulesFolder $Match.Groups[1].Value
        $DirectoryPath = Split-Path -Parent $FilePath
        if (-not (Test-Path $DirectoryPath)) { New-Item $DirectoryPath -ItemType Directory | Out-Null }
        Write-Host " > Extracting $($_.FullName)"
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $FilePath, $true) | Out-Null
      }
    }
  $Zip.Dispose()
  Import-Module SwissChocolateyLab -Force


  # Make sure that Update-SwissHost function gets called when this user logs in
  # https://stackoverflow.com/questions/40569045/register-scheduledjob-as-the-system-account-without-having-to-pass-in-credentia
  # tasks vs. jobs: https://devblogs.microsoft.com/scripting/using-scheduled-tasks-and-scheduled-jobs-in-powershell/
  # Output: %LOCALAPPDATA%\Microsoft\Windows\PowerShell\ScheduledJobs\$JobName
  if (-not $Scheduled)
  {
    $accountId = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $AutoUpdateTrigger = New-JobTrigger -AtLogOn
    $JobOptions = New-ScheduledJobOption -StartIfOnBattery -RunElevated
    $Task = Get-ScheduledJob -Name $Config.AutoUpdateJobName -ErrorAction SilentlyContinue
    if ($null -ne $Task)
    {
      Unregister-ScheduledJob $Task -Confirm:$False
    }
    if ($Config.AutoUpdateEnabled)
    {
      Write-Host "Registering startup job to run Update-SwissHost: $($Config.AutoUpdateJobName)"
      Register-ScheduledJob -Name $Config.AutoUpdateJobName -Trigger $AutoUpdateTrigger -ScheduledJobOption $JobOptions -ScriptBlock { Import-Module "SwissChocolateyLab" ; Update-SwissHost -Scheduled } | Out-Null
      $TaskPrincipal = New-ScheduledTaskPrincipal -UserID $accountId -LogonType Interactive -RunLevel Highest
      Set-ScheduledTask -TaskPath '\Microsoft\Windows\PowerShell\ScheduledJobs' -TaskName $Config.AutoUpdateJobName -Principal $TaskPrincipal | Out-Null
    }
  }
  elseif (-not $Config.AutoUpdateEnabled)
  {
    # If the config disables auto-update but we're currently running an auto-update, use another task to unschedule this in the future
    $RemoveScheduledJobName = "Remove$($Config.AutoUpdateJobName)"
    Write-Host "Removing startup job using a helper: $RemoveScheduledJobName"
    $RemoveScheduledJobTrigger = New-JobTrigger -Once -At (get-date).AddSeconds(10)
    $JobOptions = New-ScheduledJobOption -StartIfOnBattery -RunElevated
    $Script = @"
      `$Task = Get-ScheduledJob -Name '$($Config.AutoUpdateJobName)' -ErrorAction SilentlyContinue
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






  # Require Hyper-V
  try
  {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    # Action: Install Hyper-V and CLI components (requires restart)
    if (((Get-WindowsOptionalFeature -Online -FeatureName *hyper-v*all*) | % { $_.State }) -contains "Disabled")
    {
      Write-Host "Installing Hyper-V..."
      Get-WindowsOptionalFeature -Online -FeatureName *hyper-v*all | Enable-WindowsOptionalFeature -Online
      if ($Config.AutoUpdateEnabled)
      {
        Restart-Computer
      }
      else
      {
        Write-Host "Auto-update is disabled. Please restart the computer and re-run $($MyInvocation.MyCommand.Name)"
      }
      return
    }

    Write-Host "Hyper-V is installed"
  }
  catch
  {
    Write-Host -ForegroundColor Red ">>>> Must be run on a Windows version that supports Hyper-V <<<<"
    return
  }
  finally
  {
    $ErrorActionPreference = $previousErrorActionPreference
  }




  # Workaround for built-in version of Pester shipped with Windows
  # https://pester.dev/docs/introduction/installation
  Install-Module -Name Pester -Force -SkipPublisherCheck




  # Install AutomatedLab to manage Hyper-V
  # https://www.verboon.info/2021/08/deploying-windows-11-in-minutes-with-automatedlab/
  Write-Host "Setting up AutomatedLab..."
  Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
  Install-Module AutomatedLab -AllowClobber
  $LabSourcesFolder = New-LabSourcesFolder -Drive $Config.AutomatedLab.SourcesFolderDrive
  Write-Host "AutomatedLab ready in $LabSourcesFolder"
  $ToolsPath = Join-Path $LabSourcesFolder "Tools/$($Config.Repository)"
  $PostInstallationActivitiesPath = Join-Path $LabSourcesFolder "PostInstallationActivities/$($Config.Repository)"



  # Extract tools and post installation activities usable by installed VM's
  Write-Host "Extract <repo>/Tools/** --> $ToolsPath"
  if (Test-Path $ToolsPath) { Remove-Item -Recurse -Force $ToolsPath }
  Expand-ZipFileDirectory -ZipFilePath $TempRepositoryZipPath -DirectoryInZipFile "Tools" -OutputPath $ToolsPath
  Write-Host "Extract <repo>/PostInstallationActivities/** --> $PostInstallationActivitiesPath"
  if (Test-Path $PostInstallationActivitiesPath) { Remove-Item -Recurse $PostInstallationActivitiesPath }
  Expand-ZipFileDirectory -ZipFilePath $TempRepositoryZipPath -DirectoryInZipFile "PostInstallationActivities" -OutputPath $PostInstallationActivitiesPath


  # 
  # Now, we're ready to use New-SwissVM
  #

}
