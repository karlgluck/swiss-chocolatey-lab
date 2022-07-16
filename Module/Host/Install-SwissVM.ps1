<#
.DESCRIPTION
  Installs a new SwissVM from the given repository in the account defined by .swisshost
#>
function Install-SwissVM {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory,Position=0)]
    [string]$Repository,

    [string]$Branch="main",

    [string]$VMName,

    [string]$UseCommonConfig,

    [string]$UserName,

    [string]$Token
  )

  # Clean up the VM name
  if (-not($PSBoundParameters.ContainsKey('VMName')) -or ($null -eq $VMName))
  {
    $VMName = $Repository -replace '[^a-zA-Z0-9]',''
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



  # Set the default UserName and Token using the host's config if they aren't provided
  if (-not($PSBoundParameters.ContainsKey('UserName') -or ($null -eq $UserName)))
  {
    $UserName = $HostConfig.UserName
  }
  if (-not($PSBoundParameters.ContainsKey('Token') -or ($null -eq $Token)))
  {
    $Token = $HostConfig.Token
  }



  # Get the config for the target project
  $GuestConfig = [PSCustomObject]@{
    HostConfig=$HostConfig
    Repository=$Repository
    Branch=$Branch
    UserName=$UserName
    Token=$Token
    AutoUpdateEnabled=$HostConfig.AutoUpdateEnabled
    AutoUpdateJobName=$HostConfig.AutoUpdateJobName
  }
  Add-Member -Name 'RawUrl' -Value "https://raw.githubusercontent.com/$($GuestConfig.UserName)/$($GuestConfig.Repository)/$($GuestConfig.Branch)" -Force -InputObject $GuestConfig -MemberType NoteProperty
  Add-Member -Name 'ApiContentsUrl' -Value "https://api.github.com/repos/$($GuestConfig.UserName)/$($GuestConfig.Repository)/contents" -Force -InputObject $GuestConfig -MemberType NoteProperty
  if ($PSBoundParameters.ContainsKey('UseCommonConfig'))
  {
    # Use a generic configuration from the main repository
    $GuestSpecificConfigUrl = "$($HostConfig.ApiContentsUrl)/Config/$UseCommonConfig.swissguest"
  }
  else
  {
    # Use a specialized config in the guest repository
    $GuestSpecificConfigUrl = "$($GuestConfig.ApiContentsUrl)/.swiss/config.json"
  }

  $GuestHeaders = @{Authorization=('token ' + $GuestConfig.Token); 'Cache-Control'='no-store'}
  try
  {
    $GuestConfigApiResponse = (Invoke-WebRequest -Method Get -Uri $GuestSpecificConfigUrl -Headers $GuestHeaders).Content | ConvertFrom-Json
    $RemoteConfig = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($GuestConfigApiResponse.content)) | ConvertFrom-Json
    Write-Host "Read guest config from $GuestSpecificConfigUrl"
  }
  catch
  {
    Write-Host -ForegroundColor Red "Missing configuration file: $GuestSpecificConfigUrl"
    if (-not($PSBoundParameters.ContainsKey('Branch')))
    {
      Write-Host -ForegroundColor Yellow "-Branch defaults to '$Branch', is that what you expected?"
    }
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
  
  


  # Use our installed SwissChocolateyLab PowerShell module to bootstrap the VM. We pass
  # files into the VM via the PostInstallationActivities folder.
  $HostModuleFolder = Join-Path ($env:PSModulePath -split ';')[0] "SwissChocolateyLab"
  if (-not (Test-Path $HostModuleFolder))
  {
    Write-Host -ForegroundColor Red "Missing host modules folder. Try Update-SwissHost? Expected: $HostModuleFolder"
    return
  }
  Compress-Archive -Force -Path $HostModuleFolder -DestinationPath (Join-Path (Get-LabSourcesLocation) "PostInstallationActivities/$($HostConfig.Repository)/PowerShellModule.zip")





  # Create a new lab that is connected to the internet
  # https://github.com/AutomatedLab/AutomatedLab/blob/develop/LabSources/SampleScripts/Introduction/05%20Single%20domain-joined%20server%20(internet%20facing).ps1
  # https://devblogs.microsoft.com/scripting/automatedlab-tutorial-part-2-create-a-simple-lab/
  # https://automatedlab.org/en/latest/PSFileTransfer/en-us/Copy-LabFileItem/
  $ExistingVirtualNetworkName = (Get-VMSwitch -SwitchType External | Select-Object -First 1).Name
  if ([string]::IsNullOrEmpty($ExistingVirtualNetworkName))
  {
    $VirtualNetworkName = "SCLNetwork"
  }
  else
  {
    $VirtualNetworkName = $ExistingVirtualNetworkName
  }
  $postInstallationActivitiesPath = Join-Path $labSources 'PostInstallationActivities'
  $postInstallActivity = ($HostConfig.PostInstallationActivities + $GuestConfig.PostInstallationActivities) | ForEach-Object {
      if (Get-Member -InputObject $_ -Name "DependencyFolderName")
      {
        $DependencyFolder = $_.DependencyFolderName
      }
      else
      {
        $DependencyFolder = $HostConfig.Repository
      }
      Get-LabPostInstallationActivity -KeepFolder -ScriptFileName $_.ScriptFileName -DependencyFolder (Join-Path $postInstallationActivitiesPath $DependencyFolder)
    }
  $tempSwissGuestPath = Join-Path ([System.IO.Path]::GetTempPath()) ".swissguest"
  New-LabDefinition -Name "$($VMName)SCLLab" -DefaultVirtualizationEngine HyperV
  Add-LabVirtualNetworkDefinition -Name $VirtualNetworkName -VirtualizationEngine HyperV -HyperVProperties @{SwitchType = 'External'; AdapterName = 'Ethernet'}
  Set-LabInstallationCredential -Username $GuestConfig.Username -Password $Repository
  $MemoryInBytes = (Invoke-Expression $GuestConfig.VirtualMachine.Memory)
  Add-LabMachineDefinition -Name $VMName -Memory $MemoryInBytes -Network $VirtualNetworkName -OperatingSystem $GuestConfig.OperatingSystem.Version -PostInstallationActivity $postInstallActivity -ToolsPath "$labSources\Tools" -ToolsPathDestination 'C:\Tools'

  # Finally, create our network and VM
  Install-Lab

  # Move the .swissguest config into the VM
  $GuestConfig | ConvertTo-Json | Out-File -FilePath $tempSwissGuestPath
  Copy-LabFileItem -Path $tempSwissGuestPath -ComputerName $VMName -DestinationFolderPath "C:\Users\$($GuestConfig.UserName)\Documents"


  # Map a network drive to the VM's Shared folder
  $AvailableDrivePath = (Compare-Object (Get-PSDrive | % { $_.Name }) (67..90 | %{[char]$_}) | Where-Object { $_.SideIndicator -eq "=>" } | Select-Object -First 1).InputObject
  $Domain = $VMName.ToUpper()
  $Username = "$Domain\$($GuestConfig.Username)"
  $Password = ConvertTo-SecureString $Repository -AsPlainText -Force
  $Credential = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList $Username, $Password
  New-PSDrive -Name $AvailableDrivePath.Substring(0,1) -PSProvider FileSystem -Persist -Root "\\$Domain\Shared" -Credential $Credential



  # Display results to the user
  Show-LabDeploymentSummary -Detailed
  Write-Host "Finished installing lab; log in with Username=$($GuestConfig.UserName) and Password=$Repository"

}
  
