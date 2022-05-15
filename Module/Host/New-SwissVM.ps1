<#
.DESCRIPTION
  Installs a new SwissVM from the given repository in the account defined by .swisshost
#>
function New-SwissVM {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory,Position=0)]
    [string]$Repository,

    [string]$Branch="main",

    [string]$VMName
  )

  # Clean up the VM name
  if(-not($PSBoundParameters.ContainsKey('VMName')))
  {
    $VMName = $Repository -replace '[^a-zA-Z0-9-]',''
  }
  if ($VMName.Length -gt 15)
  {
    $VMName = $VMName.Substring(0,15)
  }

  # Load our configuration (expect it to exist)
  $HostConfigPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swisshost"
  if (Test-Path $HostConfigPath)
  {
    Write-Host "Loading host config from $HostConfigPath"
    $HostConfig = Get-Content $HostConfigPath | ConvertFrom-Json
  }
  else
  {
    Write-Host -ForegroundColor Red "No configuration found. Try Update-SwissHost? Expected: $ConfigPath"
    return      
  }

  # Get the config for the target project at the moment
  $GuestConfig = [PSCustomObject]@{Repository=$Repository; Branch=$Branch; UserName=$HostConfig.UserName; Token=$HostConfig.Token}
  $Headers = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}
  $GuestSpecificConfigUrl = "https://raw.githubusercontent.com/$($GuestConfig.UserName)/$($GuestConfig.Repository)/$($GuestConfig.Branch)/.swiss/config.json"
  try
  {
    $RemoteConfig = (Invoke-WebRequest -Method Get -Uri $GuestSpecificConfigUrl -Headers $Headers).Content | ConvertFrom-Json
    Write-Host "Read guest config from $GuestSpecificConfigUrl"
  }
  catch
  {
    Write-Host -ForegroundColor Red "Missing configuration file: $GuestSpecificConfigUrl"
    return
  }
  finally
  {
    if (Test-Path 'variable:RemoteConfig')
    {
      # Move properties into GuestConfig
      $RemoteConfig.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" } | ForEach-Object { Add-Member -Name $_.Name -Value $_.Value -Force -InputObject $GuestConfig -MemberType NoteProperty }
      Remove-Variable -Name RemoteConfig
    }
  }

  
  # Make sure that we have the ISO to install this operating system
  $labSources = Get-LabSourcesLocation
  $labSourcesISOPath = Join-Path $labSources "ISOs"
  Write-Host -ForegroundColor Yellow "Checking for a Windows .iso file in $labSourcesISOPath using Fido ($($HostConfig.FidoScriptUrl))"
  Invoke-Expression ( 'function Get-WindowsIsoUrl {' + (New-Object System.Net.WebClient).DownloadString($HostConfig.FidoScriptUrl + '?ts=' + (Get-Date -uformat %s)) + '}');
  $isoUrl = Get-WindowsIsoUrl -Win $GuestConfig.OperatingSystem.Name -Rel $GuestConfig.OperatingSystem.Release -Ed $GuestConfig.OperatingSystem.Edition -Lang $GuestConfig.OperatingSystem.Language -Arch $GuestConfig.OperatingSystem.Architecture -GetUrl $True
  $isoFileName = [regex]::Match($isoUrl, '.*\/(.*\.iso).*').Groups[1].Value

  $downloadedFileFullPath = Join-Path $labSourcesISOPath $isoFileName
  if (Test-Path -Path $downloadedFileFullPath -PathType Leaf)
  {
      Write-Host "Matching installer available at $downloadedFileFullPath"
  }
  else
  {
      Write-Host "Downloading $isoFileName from $isoUrl..."
      try
      {
          Invoke-WebRequest -UseBasicParsing -Uri $isoUrl -OutFile $downloadedFileFullPath
      }
      catch
      {
          Write-Host -ForegroundColor Red ">>>> Failed to download Windows from '$isoUrl' to '$downloadedFileFullPath' <<<<"
          return
      }
      Write-Host "Downloaded matching installer to $downloadedFileFullPath"
  }
  
  


  # Create a new lab that is connected to the internet
  # https://github.com/AutomatedLab/AutomatedLab/blob/develop/LabSources/SampleScripts/Introduction/05%20Single%20domain-joined%20server%20(internet%20facing).ps1
  # https://devblogs.microsoft.com/scripting/automatedlab-tutorial-part-2-create-a-simple-lab/
  # https://automatedlab.org/en/latest/PSFileTransfer/en-us/Copy-LabFileItem/
  $LabName = "$($VMName)SwissLab"
  $VirtualNetworkName = "$($VMName)SwissNet"
  $postInstallationActivitiesPath = Join-Path $labSources 'PostInstallationActivities'
  $postInstallActivity = ($HostConfig.PostInstallationActivities + $GuestConfig.PostInstallationActivities) | ForEach-Object { Get-LabPostInstallationActivity -ScriptFileName $_.ScriptFileName -DependencyFolder (Join-Path $postInstallationActivitiesPath $_.DependencyFolderName) }
  $tempSwissGuestPath = Join-Path ([System.IO.Path]::GetTempPath()) ".swissguest"
  New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV
  Add-LabVirtualNetworkDefinition -Name $VirtualNetworkName -VirtualizationEngine HyperV -HyperVProperties @{SwitchType = 'External'; AdapterName = 'Ethernet'}
  Set-LabInstallationCredential -Username $HostConfig.Username -Password $Repository
  $MemoryInBytes = (Invoke-Expression $GuestConfig.VirtualMachine.Memory)
  Add-LabMachineDefinition -Name $VMName -Memory $MemoryInBytes -Network $VirtualNetworkName -OperatingSystem $GuestConfig.OperatingSystem.Version -PostInstallationActivity $postInstallActivity -ToolsPath "$labSources\Tools" -ToolsPathDestination 'C:\Tools'
  Install-Lab
  $GuestConfig | ConvertTo-Json | Out-File -FilePath $tempSwissGuestPath
  Copy-LabFileItem -Path $tempSwissGuestPath -ComputerName $VMName -DestinationFolderPath "C:\Users\$($HostConfig.Username)\Documents"
  #Invoke-LabCommand -ActivityName 'ConfigureSwiss' -ComputerName $VMName -Variable HostConfig,GuestConfig -UseLocalCredential -Retries 3 -RetryIntervalInSeconds 20 `
  #  -ScriptBlock {$GuestConfig | ConvertTo-Json | Out-File -FilePath (Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swissguest")}}
  Show-LabDeploymentSummary -Detailed

  
  Write-Host "Finished installing lab; log in with Username=$($HostConfig.Username) and Password=$Repository"

}
  
