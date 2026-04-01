param(
    [int]$Port = 9070,
    [string]$BindHost = "localhost"
)

$modulePath = Resolve-Path (Join-Path $PSScriptRoot "../milkit/milkit.psm1")
Import-Module $modulePath -Force

$app = New-App -Root $PSScriptRoot -Name "radiolog"

function Send-LocalTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $true)]
        [string]$ContentType
    )

    $path = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $null = $Response.NotFound(@{ message = "not found" })
        return
    }

    $content = Get-Content -LiteralPath $path -Raw
    $null = $Response.Status(200)
    $null = $Response.Text($content, $ContentType)
}

Add-Route $app GET "/health" {
    param($req, $res)
    $null = $res.Ok(@{ status = "ok" })
}

Add-Route $app GET "/" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "index.html" -ContentType "text/html; charset=utf-8"
}

Add-Route $app GET "/index.html" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "index.html" -ContentType "text/html; charset=utf-8"
}

Add-Route $app GET "/view" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "view.html" -ContentType "text/html; charset=utf-8"
}

Add-Route $app GET "/view.html" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "view.html" -ContentType "text/html; charset=utf-8"
}

Add-Route $app GET "/style.css" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "style.css" -ContentType "text/css; charset=utf-8"
}

Add-Route $app GET "/view.css" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "view.css" -ContentType "text/css; charset=utf-8"
}

Add-Route $app GET "/script.js" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "script.js" -ContentType "application/javascript; charset=utf-8"
}

Add-Route $app GET "/view.js" {
    param($req, $res)
    Send-LocalTextFile -Response $res -FileName "view.js" -ContentType "application/javascript; charset=utf-8"
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
