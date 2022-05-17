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

  $GuestConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swissguest"

  # Get the repository's configuration file
  if ($null -ne $Bootstrap)
  {
    Write-Host "Bootstrapping sandbox '${env:ComputerName}'"

    $HostConfig = [PSCustomObject]@{}

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
      $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $GenericHostConfigUrl -Headers $Headers).Content | ConvertFrom-Json
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

    # Save the host config into the guest config object
    $GuestConfig = [PSCustomObject]@{ HostConfig = $HostConfig }

    # Parse the guest's repository configuration from GuestUrl
    $Match = [RegEx]::Match($Bootstrap.GuestUrl, 'github\.com\/([^\/]+)\/([^\/]+)\/(\S+)\/?')
    if ($Match.Success)
    {
      Add-Member -Name 'UserName' -Value $Match.Groups[1].Value -Force -InputObject $GuestConfig -MemberType NoteProperty
      Add-Member -Name 'Repository' -Value $Match.Groups[2].Value -Force -InputObject $GuestConfig -MemberType NoteProperty
      Add-Member -Name 'Branch' -Value $Match.Groups[3].Value -Force -InputObject $GuestConfig -MemberType NoteProperty
      Add-Member -Name 'RawUrl' -Value "https://raw.githubusercontent.com/$($GuestConfig.UserName)/$($GuestConfig.Repository)/$($GuestConfig.Branch)" -Force -InputObject $GuestConfig -MemberType NoteProperty
      Add-Member -Name 'ZipUrl' -Value "https://github.com/$($GuestConfig.UserName)/$($GuestConfig.Repository)/archive/refs/heads/$($GuestConfig.Branch).zip" -Force -InputObject $GuestConfig -MemberType NoteProperty
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> Guest repository URL doesn't match expected format (see README.md) <<<<"
      return
    }

    # Prevent accidental use of the Bootstrap variable later in the script
    Remove-Variable -Name 'Bootstrap'
  }
  else
  {
    # Expect a config file to exist, otherwise we can't know what to do
    if (Test-Path $GuestConfigPath)
    {
      Write-Host "Loading guest config from $GuestConfigPath"
      $GuestConfig = Get-Content $GuestConfigPath | ConvertFrom-Json
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> FATAL: Missing config file. Try bootstrapping again? (see README.md) <<<<"
      Write-Host -ForegroundColor Red "Expected: $GuestConfigPath"
      return
    }
  }


  # Grab the config from the guest repository and merge it into $GuestConfig
  $GuestConfigUrl = "$($GuestConfig.RawUrl)/.swiss/config.json"
  try
  {
    $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $GuestConfigUrl -Headers $Headers).Content | ConvertFrom-Json
    Write-Host "Using guest-specific config: $GuestConfigUrl"
  }
  finally
  {
    if (Test-Path 'variable:RemoteConfig')
    {
      # Move properties into Config
      $RemoteConfig.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" } | ForEach-Object { Add-Member -Name $_.Name -Value $_.Value -Force -InputObject $GuestConfig -MemberType NoteProperty }
      Remove-Variable -Name RemoteConfig
    }
  }

  # Write the configuration file
  ConvertTo-Json $GuestConfig | Out-File -FilePath $GuestConfigPath




  # Derived variables
  $GuestHeaders = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}
  $ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"
  $PackagesConfigUrl = "$($GuestConfig.RawUrl)/.swiss/packages.config"
  $PackagesConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "packages.config"




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
  if (Test-Command 'choco')
  {
    choco upgrade chocolatey
  }
  else
  {
    Set-ExecutionPolicy Bypass -Scope Process -Force;
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Global configuration
    choco feature enable -n=allowGlobalConfirmation --no-color | Out-Null
    choco feature enable -n=exitOnRebootDetected --no-color | Out-Null
  }




  # Download <guest-repo>/.swiss/packages.config
  try
  {
    Invoke-WebRequest -Method Get -Uri $PackagesConfigUrl -Headers $GuestHeaders -OutFile $PackagesConfigPath
    Write-Host "Installing choco packages from $PackagesConfigUrl"
  }
  catch
  {
    if (-not (Test-Path $PackagesConfigPath))
    {
      Write-Host -ForegroundColor Yellow @"
Missing Chocolatey configuration. No packages will be installed. Expecting either:
    * $PackagesConfigUrl
    * $PackagesConfigPath
"@
    }
  }




  # Install packages.config using Chocolatey
  if (Test-Path $PackagesConfigPath)
  {
    $packagesAlreadyInstalled = (choco list --limit-output --local-only) | ForEach-Object { $_.Split("|")[0] }
    $packagesRequiredByConfig = Select-Xml -Path $PackagesConfigPath -XPath "packages/package" | ForEach-Object { $_.Node.id }
    $packagesToInstall = Compare-Object -ReferenceObject $packagesAlreadyInstalled -DifferenceObject $packagesRequiredByConfig | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { $_.InputObject }

    if ($packagesToInstall.Count -gt 0)
    {
      [void](& choco install $PackagesConfigPath --limit-output --no-color -y)
      $chocoExitCode = $LASTEXITCODE

      $packagesSubsequentlyInstalled = (choco list --limit-output --local-only) | ForEach-Object { $_.Split("|")[0] }
      $packagesNotInstalled = Compare-Object -ReferenceObject $packagesSubsequentlyInstalled -DifferenceObject $packagesRequiredByConfig | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { $_.InputObject }
      if ($packagesNotInstalled.Count -gt 0)
      {
        Write-Host -ForegroundColor Yellow "Not all packages could be installed. Missing: $($packagesNotInstalled -join ', ')"
        $chocoExitCode = 9999
      }
      if (@(350, 1604, 1614, 1641, 3010, 9999) -contains $chocoExitCode)
      {
        Write-Host -ForegroundColor Yellow "Chocolatey exited with $chocoExitCode. Restart your computer to continue installing packages"
        if ($GuestConfig.AutoUpdateEnabled)
        {
          Restart-Computer
        }
      }
    }
  }



}
