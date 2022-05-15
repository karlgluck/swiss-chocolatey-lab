<#
.DESCRIPTION
  Extracts all contents of a sub-directory in a ZIP file into a target directory
#>
function Expand-ZipFileDirectory
{
  Param(
    [Parameter(Mandatory)]
    [string]$ZipFilePath,

    [Parameter(Mandatory)]
    [string]$DirectoryInZipFile,

    [Parameter(Mandatory)]
    [string]$OutputPath
  )

  $DirectoryRegex = "\/" + ($DirectoryInZipFile.Trim('/\') -replace "/","\/") + "\/(.*)"
  try
  {
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($ZipFilePath)
    $Zip.Entries | 
      Where-Object { $_.Name -ne "" } |
      ForEach-Object {
        $Match = [RegEx]::Match($_.FullName, $DirectoryRegex)
        if ($Match.Success)
        {
          $OutputFilePath = Join-Path $OutputPath $Match.Groups[1].Value
          $OutputDirectoryPath = Split-Path -Parent $OutputFilePath
          Write-Host " > Extracting $($_.FullName)"
          if (-not (Test-Path $OutputDirectoryPath)) { New-Item $OutputDirectoryPath -ItemType Directory | Out-Null }
          [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $OutputFilePath, $true) | Out-Null
        }
      }
  }
  finally
  {
    $Zip.Dispose()
  }

}
