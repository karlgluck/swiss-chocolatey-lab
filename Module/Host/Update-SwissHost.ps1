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
      Write-Host -ForegroundColor Red "Must run in an Administrator PowerShell terminal (open with Win+X, A)"
      return
  }
  
  if ($Bootstrap -ne $null)
  {
    Write-Host "Bootstrapping!"
  }
}
