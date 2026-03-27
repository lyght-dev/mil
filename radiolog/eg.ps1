param(
    [int]$Port = 9070,
    [string]$BindHost = "localhost"
)

$modulePath = Resolve-Path (Join-Path $PSScriptRoot "../milkit/milkit.psm1")
Import-Module $modulePath -Force

$app = New-App -Root $PSScriptRoot -Name "radiolog"

Add-Route $app GET "/health" {
    param($req, $res)
    $null = $res.Ok(@{ status = "ok" })
}

Use-Static $app "/" "./" -DefaultDocument @("index.html")

Write-Host ("[radiolog] serving on http://{0}:{1}/" -f $BindHost, $Port)
if ($BindHost -eq "localhost") {
    Start-App -App $app -Prefix @(
        ("http://+:{0}/" -f $Port)
    )
}
else {
    Start-App -App $app -Port $Port -BindHost $BindHost
}
