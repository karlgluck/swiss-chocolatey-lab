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
    [Switch]$AtStartup
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
      Add-Member -Name 'Username' -Value $Match.Groups[1].Value -Force -InputObject $Config -MemberType NoteProperty
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

  # Now that we have the config, define the rest of the local variables
  $GenericConfigUrl = "$($Config.RawUrl)/Config/.swisshost"
  $HostSpecificConfigUrl = "$($Config.RawUrl)/Config/${env:ComputerName}.swisshost"
  $Headers = @{Authorization=@('token ',$Config.Token) -join ''; 'Cache-Control'='no-cache'}

  # Require Administrator privileges
  if (-not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
  {
    Write-Host -ForegroundColor Red ">>>> Must run in an Administrator PowerShell terminal (open with Win+X, A) <<<<"
    return
  }

  # Grab the configuration from the repository and merge it into $Config
  $RemoteConfig = @{}
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
    }
    Remove-Variable -Name RemoteConfig
  }

  # Write the host configuration file
  ConvertTo-Json $Config | Out-File -FilePath $ConfigPath

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
      Write-Host "Restarting (run the script again)..."
      Restart-Computer -Delay 5
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

}

