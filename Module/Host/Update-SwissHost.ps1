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
    $Bootstrap,
    [Switch]$AtStartup
  )

  # Local Variables
  $Config = @{}
  $ConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swisshost"

  # Preamble
  if ($null -ne $Bootstrap)
  {
    Write-Host "Bootstrapping '${env:ComputerName}'"
  }
  else
  {

  }

  # Require Administrator privileges
  if (-not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
  {
    Write-Host -ForegroundColor Red ">>>> Must run in an Administrator PowerShell terminal (open with Win+X, A) <<<<"
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

  # Initialize the config with whatever already exists
  if (Test-Path $ConfigPath)
  {
    Write-Host "Loading host config from $ConfigPath"
    (Get-Content $ConfigPath | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $Config[$_.Name]= $_.Value }
  }

  # Get the repository's configuration file
  if ($null -ne $Bootstrap)
  {
    # Save the access token
    $Config['token'] = $Bootstrap['Token']

    # Parse repository configuration from the URL
    $Match = [RegEx]::Match($Bootstrap['Url'], '[.]com\/([^\/]+)\/([^\/]+)\/(\S+)\/Module\/Host\/Update-SwissHost.ps1')
    if ($Match.Success)
    {
      $Config['username'] = $Match.Groups[1].Value
      $Config['repository'] = $Match.Groups[2].Value
      $Config['branch'] = $Match.Groups[3].Value
      $Config['raw_url'] = "https://raw.githubusercontent.com/$($Config['username'])/$($Config['repository'])/$($Config['branch'])"
      $Config['zip_url'] = "https://github.com/$($Config['username'])/$($Config['repository'])/archive/refs/heads/$($Config['branch']).zip"
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> Bootstrapping URL doesn't match expected format (see README.md) <<<<"
      return
    }
  }
  else
  {
    # Expect a config file to exist, otherwise we can't know what to do
    if (-not (Test-Path $ConfigPath))
    {
      Write-Host -ForegroundColor Red ">>>> FATAL: Missing config file. Try bootstrapping again? <<<<"
      Write-Host -ForegroundColor Red "Expected: $ConfigPath"
      return
    }
  }

  # More local variables
  $GenericConfigUrl = "$($Config['raw_url'])/Config/.swisshost"
  $HostSpecificConfigUrl = "$($Config['raw_url'])/Config/${env:ComputerName}.swisshost"
  $Headers = @{Authorization=@('token ',$Config['Token']) -join ''; 'Cache-Control'='no-cache'}

  #Invoke-WebRequest -Method Get -Uri $HostSpecificConfigUrl -Headers $Headers
  #Invoke-WebRequest -Method Get -Uri $GenericConfigUrl -Headers $Headers


  # Grab the configuration from the repository and merge it into $Config
  $RemoteConfig = @{}
  try
  {
    $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $HostSpecificConfigUrl -Headers $Headers).Content | ConvertFrom-Json
    Write-Host "Found a config for this host: $HostSpecificConfigUrl"
  }
  catch
  {
    try
    {
      $RemoteConfig = Invoke-WebRequest -Method Get -Uri $GenericConfigUrl -Headers $Headers
      Write-Host "Applying generic host config: $GenericConfigUrl"
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
      $RemoteConfig.PSObject.Properties | ForEach-Object { $Config[$_.Name] = $Config[$_.Value] }
    }
    Remove-Variable -Name RemoteConfig
  }

  # Write the host configuration file
  ConvertTo-Json $Config | Out-File -FilePath $ConfigPath


}
