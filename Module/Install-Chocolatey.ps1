function Install-Chocolatey
{
  [CmdletBinding()]
  Param()
    
  if (Test-CommandExists 'choco')
  {
    choco upgrade chocolatey
  }
  else
  {
    Set-ExecutionPolicy Bypass -Scope Process -Force;
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Global configuration
    choco feature enable -n=allowGlobalConfirmation --no-color | Out-Null
    choco feature enable -n=exitOnRebootDetected --no-color | Out-Null
  }
  
}