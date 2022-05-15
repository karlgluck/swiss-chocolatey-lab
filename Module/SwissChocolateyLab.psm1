
$Paths = @($PSScriptRoot)

# Load all the "Host" functions if we're on the host
if (Test-Path (Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swisshost"))
{
    $Paths += Join-Path $PSScriptRoot "Host"
}

# Load all the "Guest" functions if we're on a guest
if (Test-Path (Join-Path ([Environment]::GetFolderPath("MyDocuments")) ".swissguest"))
{
    $Paths += Join-Path $PSScriptRoot "Guest"
}

# Load each file and export it as a function from the module
$Paths | Where-Object { Test-Path $_ } | Get-ChildItem -File -Filter "*.ps1" | ForEach-Object { . $_.FullName ; Export-ModuleMember -Function ([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
