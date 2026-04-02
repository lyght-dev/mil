param(
    [int]$Port = 9070,
    [string]$BindHost = "localhost"
)

$modulePath = Resolve-Path (Join-Path $PSScriptRoot "../milkit/milkit.psm1")
Import-Module $modulePath -Force

$app = New-App -Root $PSScriptRoot -Name "radiolog"

Use-Static $app "/" "./" -DefaultDocument @("index.html")

Start-App -App $app -Prefix @(("http://+:{0}/" -f $Port))
