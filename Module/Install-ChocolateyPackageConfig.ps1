<#
.DESCRIPTION
  Installs packages from a Chocolatey package config file
#>
function Install-ChocolateyPackageConfig
{
  Param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if (-not (Test-Path $Path))
  {
    Write-Host -ForegroundColor Yellow "Package file not found: $Path"
    return [PSCustomObject]@{Finished=$True; ExitCode=-1; RestartRequired=$False; RemainingPackages=@()}
  }

  $packagesAlreadyInstalled = (choco list --limit-output --local-only) | ForEach-Object { $_.Split("|")[0] }
  $packagesRequiredByConfig = Select-Xml -Path $Path -XPath "packages/package" | ForEach-Object { $_.Node.id }
  $packagesToInstall = Compare-Object -ReferenceObject $packagesAlreadyInstalled -DifferenceObject $packagesRequiredByConfig | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { $_.InputObject }

  if ($packagesToInstall.Count -gt 0)
  {
    [void](& choco install $Path --limit-output --no-color -y)
    $chocoExitCode = $LASTEXITCODE

    $packagesSubsequentlyInstalled = (choco list --limit-output --local-only) | ForEach-Object { $_.Split("|")[0] }
    $packagesNotInstalled = Compare-Object -ReferenceObject $packagesSubsequentlyInstalled -DifferenceObject $packagesRequiredByConfig | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { $_.InputObject }
    if ($packagesNotInstalled.Count -gt 0)
    {
      Write-Host -ForegroundColor Yellow "Not all packages could be installed. Missing: $($packagesNotInstalled -join ', ')"
      $chocoExitCode = 9999
    }
  }
  else
  {
    $chocoExitCode = 0
  }

  $restartRequired = (@(350, 1604, 1614, 1641, 3010) -contains $chocoExitCode)

  return [PSCustomObject]@{
    Finished=(($packagesNotInstalled.Count -eq 0) -and (-not $restartRequired))
    ExitCode=$chocoExitCode
    RestartRequired=$restartRequired
    PackagesNotInstalled=$packagesNotInstalled
    }
}