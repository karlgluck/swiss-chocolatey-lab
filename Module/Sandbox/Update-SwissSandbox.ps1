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
  $GuestHeaders = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}
  $ModulesFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"
  $PackagesConfigUrl = "$($GuestConfig.RawUrl)/.swiss/packages.config"
  $PackagesConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "packages.config"




  # Download the latest copy of the host repository
  $TempRepositoryZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($GuestConfig.Username)-$($GuestConfig.Repository)-$([System.IO.Path]::GetRandomFileName()).zip"
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


}
