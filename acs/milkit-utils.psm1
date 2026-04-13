function Test-Blank {
    param(
        [AllowNull()]
        [string]$Value
    )

    return [string]::IsNullOrWhiteSpace($Value)
}

Export-ModuleMember -Function Test-Blank
