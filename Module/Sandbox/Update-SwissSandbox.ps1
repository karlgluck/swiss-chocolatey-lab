<#
.DESCRIPTION
  Installs or updates SCL into a Windows Sandbox. See README.md for the one-liner
.NOTES
  Can be called in 2 ways: first-time bootstrapping or manually.
#>
function Update-SwissSandbox {
  [CmdletBinding()]
  Param (
    [PSCustomObject]$Bootstrap
  )

  $ProjectConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swisssandbox"

  # Get the repository's configuration file
  if ($null -ne $Bootstrap)
  {
    Write-Host "Bootstrapping sandbox '${env:ComputerName}'"

    $HostConfig = [PSCustomObject]@{Token = $Bootstrap.Token}
    $HostHeaders = @{Authorization=('token ' + $HostConfig.Token); 'Cache-Control'='no-store'}

    # Save the access token
    Add-Member -Name 'Token' -Value $Bootstrap.Token -Force -InputObject $HostConfig -MemberType NoteProperty

    # Parse the host's repository configuration from HostUrl
    $Match = [RegEx]::Match($Bootstrap.HostUrl, 'githubusercontent\.com\/([^\/]+)\/([^\/]+)\/(\S+)\/Module\/Sandbox\/Update-SwissSandbox.ps1')
    if ($Match.Success)
    {
      Add-Member -Name 'UserName' -Value $Match.Groups[1].Value -Force -InputObject $HostConfig -MemberType NoteProperty
      Add-Member -Name 'Repository' -Value $Match.Groups[2].Value -Force -InputObject $HostConfig -MemberType NoteProperty
      Add-Member -Name 'Branch' -Value $Match.Groups[3].Value -Force -InputObject $HostConfig -MemberType NoteProperty
      Add-Member -Name 'RawUrl' -Value "https://raw.githubusercontent.com/$($HostConfig.UserName)/$($HostConfig.Repository)/$($HostConfig.Branch)" -Force -InputObject $HostConfig -MemberType NoteProperty
      Add-Member -Name 'ZipUrl' -Value "https://github.com/$($HostConfig.UserName)/$($HostConfig.Repository)/archive/refs/heads/$($HostConfig.Branch).zip" -Force -InputObject $HostConfig -MemberType NoteProperty
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> Bootstrapping URL doesn't match expected format (see README.md) <<<<"
      return
    }

    $GenericHostConfigUrl = "$($HostConfig.RawUrl)/Config/.swisshost"

    try
    {
      $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $GenericHostConfigUrl -Headers $HostHeaders).Content | ConvertFrom-Json
      Write-Host "Using generic host config: $GenericHostConfigUrl"
    }
    catch
    {
      Write-Host -ForegroundColor Red ">>>> Missing both default and host-specific config files in SCL repository <<<<"
      Write-Host -ForegroundColor Red "Expected either:"
      Write-Host -ForegroundColor Red " * $GenericHostConfigUrl"
      Write-Host -ForegroundColor Red " * $HostSpecificConfigUrl"
      return;
    }
    finally
    {
      if (Test-Path 'variable:RemoteConfig')
      {
        # Move properties into Config
        $RemoteConfig.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" } | ForEach-Object { Add-Member -Name $_.Name -Value $_.Value -Force -InputObject $HostConfig -MemberType NoteProperty }
        Remove-Variable -Name RemoteConfig
      }
    }

    # Save the host config into the config object, then dispose of it
    $ProjectConfig = [PSCustomObject]@{ HostConfig = $HostConfig; Token = $HostConfig.Token }
    Remove-Variable -Name HostConfig

    # Parse the repository configuration from ProjectUrl
    $Match = [RegEx]::Match($Bootstrap.ProjectUrl, 'github\.com\/([^\/]+)\/([^\/]+)\/(\S+)\/?')
    if ($Match.Success)
    {
      Add-Member -Name 'UserName' -Value $Match.Groups[1].Value -Force -InputObject $ProjectConfig -MemberType NoteProperty
      Add-Member -Name 'Repository' -Value $Match.Groups[2].Value -Force -InputObject $ProjectConfig -MemberType NoteProperty
      Add-Member -Name 'Branch' -Value $Match.Groups[3].Value -Force -InputObject $ProjectConfig -MemberType NoteProperty
      Add-Member -Name 'RawUrl' -Value "https://raw.githubusercontent.com/$($ProjectConfig.UserName)/$($ProjectConfig.Repository)/$($ProjectConfig.Branch)" -Force -InputObject $ProjectConfig -MemberType NoteProperty
      Add-Member -Name 'ZipUrl' -Value "https://github.com/$($ProjectConfig.UserName)/$($ProjectConfig.Repository)/archive/refs/heads/$($ProjectConfig.Branch).zip" -Force -InputObject $ProjectConfig -MemberType NoteProperty
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> repository URL doesn't match expected format (see README.md) <<<<"
      return
    }
    
    # If the usernames of the repositories don't match, ask the user if they want to access the repo with a different token
    if ($ProjectConfig.UserName -ne $ProjectConfig.HostConfig.UserName)
    {
      Write-Host "Repository is from a different user. Enter another access token if necessary, or leave it blank."
      $OverrideToken = Read-Host -Prompt "Repository GitHub Token"
      if ($OverrideToken.StartsWith("ghp_"))
      {
        $ProjectConfig.Token = $OverrideToken
      }
    }

    # Prevent accidental use of the Bootstrap variable later in the script
    Remove-Variable -Name 'Bootstrap'
  }
  else
  {
    # Expect a config file to exist, otherwise we can't know what to do
    if (Test-Path $ProjectConfigPath)
    {
      Write-Host "Loading config from $ProjectConfigPath"
      $ProjectConfig = Get-Content $ProjectConfigPath | ConvertFrom-Json
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> FATAL: Missing config file. Try bootstrapping again? (see README.md) <<<<"
      Write-Host -ForegroundColor Red "Expected: $ProjectConfigPath"
      return
    }
  }



  # Derived variables
  $SandboxHeaders = @{Authorization=('token ' + $ProjectConfig.Token); 'Cache-Control'='no-store'}
  $ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"
  $PackagesConfigUrl = "$($ProjectConfig.RawUrl)/.swiss/packages.config"
  $PackagesConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "packages.config"




  # Grab the config from the sandbox repository and merge it into $ProjectConfig
  $ProjectConfigUrl = "$($ProjectConfig.RawUrl)/.swiss/config.json"
  try
  {
    $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $ProjectConfigUrl -Headers $SandboxHeaders).Content | ConvertFrom-Json
    Write-Host "Using repository config: $ProjectConfigUrl"
  }
  finally
  {
    if (Test-Path 'variable:RemoteConfig')
    {
      # Move properties into Config
      $RemoteConfig.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" } | ForEach-Object { Add-Member -Name $_.Name -Value $_.Value -Force -InputObject $ProjectConfig -MemberType NoteProperty }
      Remove-Variable -Name RemoteConfig
    }
  }

  # Write the configuration file
  ConvertTo-Json $ProjectConfig | Out-File -FilePath $ProjectConfigPath




  # Download the latest copy of the host repository
  $TempRepositoryZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($ProjectConfig.HostConfig.UserName)-$($ProjectConfig.HostConfig.Repository)-$([System.IO.Path]::GetRandomFileName()).zip"
  try
  {
    Write-Host "Downloading latest '$($ProjectConfig.HostConfig.Repository)' branch $($ProjectConfig.HostConfig.Branch) -> $TempRepositoryZipPath"
    Invoke-WebRequest -Headers $HostHeaders -Uri $ProjectConfig.HostConfig.ZipUrl -OutFile $TempRepositoryZipPath
    $ZipFileHash = (Get-FileHash $TempRepositoryZipPath -Algorithm SHA256).Hash
    Write-Host " > Downloaded, SHA256 = $ZipFileHash"
  }
  catch
  {
    Write-Host -ForegroundColor Red "Unable to download host repository ZIP file from $($ProjectConfig.HostConfig.ZipUrl)"
    return
  }




  # Install <host-repo>/Module/** as a PowerShell module
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




  # Install Chocolatey
  Install-Chocolatey




  # Download <repo>/.swiss/packages.config
  Write-Host "Installing packages.config..."
  try
  {
    Invoke-WebRequest -Method Get -Uri $PackagesConfigUrl -Headers $SandboxHeaders -OutFile $PackagesConfigPath
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
      Write-Host -ForegroundColor Red " > Installing packages requires a restart, but we are running in a sandbox and restarting will erase all data. Some packages may not work."
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
    * $PackagesConfigUrl
    * $PackagesConfigPath
"@
  }


}
