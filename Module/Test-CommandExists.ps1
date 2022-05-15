<#
.DESCRIPTION
  Returns true/false depending on whether the given command is available to the current PowerShell session
#>
function Test-CommandExists
{
  Param(
    [string]$Name
  )

  $previousValue = $ErrorActionPreference
  $ErrorActionPreference = 'Stop'

  try
  {
    if (Get-Command $Name)
    {
      return $True
    }
  }
  catch 
  {
    return $False
  }
  finally
  {
    $ErrorActionPreference = $previousValue
  }

}
