<#
.DESCRIPTION
  Cleans up a SCL project. Deletes the VM and any associated network shared drives.
#>
function Remove-SwissVM {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory,Position=0)]
    [string]$VMName
  )

  #Remove-VM $VMName
  Remove-Lab -Name "${VMName}SCLLab" -RemoveExternalSwitches

  # TODO: Get logical mapped drives, find any that map to this VM's domain, and remove them.
  #
  # Get-WmiObject -ClassName Win32_MappedLogicalDisk | Select-Object PSComputerName,Name,ProviderName

  $NamesToRemove = Get-WmiObject -ClassName Win32_MappedLogicalDisk | Select-Object PSComputerName,Name,ProviderName | Where-Object { $_.ProviderName -eq "\\$VMName\Shared" } | ForEach-Object { $_.Name.Substring(0, 1) }
  Remove-PSDrive -Name $NamesToRemove

}
