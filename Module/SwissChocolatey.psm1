
function FooBar {
    Param ()
    Write-Host "HELLO"
}

Export-ModuleMember -Function 'FooBar'