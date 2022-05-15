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
    if (Test-Path $ConfigPath)
    {
      Write-Host "Already installed; running update instead. If you want to bootstrap again, delete '$ConfigPath'."
      Write-Host -NoNewline "Continuing in 3... "
      Start-Sleep 1
      Write-Host -NoNewLine "2... "
      Start-Sleep 1
      Write-Host -NoNewLine "1... "
      Start-Sleep 1
      Write-Host "continuing update"
      Remove-Variable -Name "Bootstrap"
    }
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

    # Grab the configuration from the repository and merge it into $Config

    # Write the host configuration file
    ConvertTo-Json $Config | Out-File -FilePath $ConfigPath
  }
  else
  {
    # Expect a config file to exist, otherwise we can't know what to do
    if (Test-Path $ConfigPath)
    {
      $Config = Get-Item $ConfigPath | ConvertFrom-Json
    }
    else
    {
      Write-Host -ForegroundColor Red ">>>> Missing config file. Try bootstrapping again? <<<<"
      Write-Host -ForegroundColor Red "Expected: $ConfigPath"
      return
    }
  }
}
