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

  # Precondition: Administrator privileges
  if (-not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
  {
    Write-Host -ForegroundColor Red ">>>> Must run in an Administrator PowerShell terminal (open with Win+X, A) <<<<"
    return
  }


  # Prerequisite: Windows version with Hyper-V
  try
  {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    # Action: Install Hyper-V and CLI components (requires restart)
    if (((Get-WindowsOptionalFeature -Online -FeatureName *hyper-v*all*) | % { $_.State }) -contains "Disabled")
    {
      Write-Host "Hyper-V is enabled"
      Get-WindowsOptionalFeature -Online -FeatureName *hyper-v*all | Enable-WindowsOptionalFeature -Online
      return
    }

    Write-Host "Hyper-V is enabled"
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
  
  if ($null -ne $Bootstrap)
  {
    Write-Host "Bootstrapping!"
  }
}
