param(
    [int]$Port = 9070,
    [string]$BindHost = "localhost"
)

$modulePath = Resolve-Path (Join-Path $PSScriptRoot "../milkit/milkit.psm1")
Import-Module $modulePath -Force

$app = New-App -Root $PSScriptRoot -Name "radiolog"

Use-Static $app "/" "./" -DefaultDocument @("index.html")

Add-Route $app GET "/health" {
    param($req, $res)
    $null = $res.Ok(@{ status = "ok" })
}

Add-Route $app GET "/view" {
    param($req, $res)
    $path = Join-Path $PSScriptRoot "view.html"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $null = $res.NotFound(@{ message = "not found" })
        return
    }

    $content = Get-Content -LiteralPath $path -Raw
    $null = $res.Status(200)
    $null = $res.Text($content, "text/html; charset=utf-8")
}

Write-Host ("[radiolog] serving on http://{0}:{1}/" -f $BindHost, $Port)
if ($BindHost -eq "localhost") {
    Start-App -App $app -Prefix @(
        ("http://+:{0}/" -f $Port)
    )
}
else {
    Start-App -App $app -Port $Port -BindHost $BindHost
}
