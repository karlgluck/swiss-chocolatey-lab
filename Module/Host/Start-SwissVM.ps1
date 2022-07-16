<#
.DESCRIPTION
  
#>
function Start-SwissVM {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory,Position=0)]
    [string]$VMName
  )

  $vm = Get-VM -Id $Name -ErrorAction SilentlyContinue
  if($vm.State -eq 'off')
  {
    Start-VM -VM $vm
  }
  vmconnect.exe $env:COMPUTERNAME $vm.Name -G $vm.Id -C 1

}
