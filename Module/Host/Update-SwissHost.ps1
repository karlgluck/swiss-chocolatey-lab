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

  # Get the repository's configuration file
  if ($null -ne $Bootstrap)
  {
    $Match = [RegEx]::Match($Bootstrap['Url'], '[.]com\/([^\/]+)\/([^\/]+)\/(\S+)\/Module\/Host\/Update-SwissHost.ps1')
    if ($Match.Success)
    {
      $Config['username'] = $Match.Groups[1].Value
      $Config['repository'] = $Match.Groups[2].Value
      $Config['branch'] = $Match.Groups[3].Value
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> URL doesn't match expected format (see README.md) <<<<"
      return
    }
  }
  else
  {
    # Not bootstrapping
  }
}
