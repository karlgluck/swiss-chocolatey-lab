<#
.DESCRIPTION
  Installs a new SwissVM from the given repository in the account defined by .swisshost
#>
function Remove-SwissVM {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory,Position=0)]
    [string]$VMName
  )

  Remove-Lab -Name "${VMName}Lab" -RemoveExternalSwitches
}
