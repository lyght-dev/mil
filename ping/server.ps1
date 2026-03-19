Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Send-BytesResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$ContentType,

        [int]$StatusCode = 200
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    # PowerShell 5 / HttpListenerResponse 호환 이슈로 ContentLength64는 설정하지 않는다.
    # OutputStream.Close()로 응답 종료는 정상 처리된다.
    # $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Send-TextResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$ContentType = "text/plain; charset=utf-8",

        [int]$StatusCode = 200
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-BytesResponse -Response $Response -Bytes $bytes -ContentType $ContentType -StatusCode $StatusCode
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [object]$Payload,

        [int]$StatusCode = 200
    )

    $json = $Payload | ConvertTo-Json -Compress -Depth 6
    Send-TextResponse -Response $Response -Text $json -ContentType "application/json; charset=utf-8" -StatusCode $StatusCode
}

function Send-InternalServerError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    try { if ($Response.OutputStream.CanWrite) { Send-TextResponse -Response $Response -Text "internal server error" -StatusCode 500 } } catch { }
}

function Get-StringField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return "" }

    return [string]$property.Value
}

function Import-Hosts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostsPath
    )

    $items = Get-Content -LiteralPath $HostsPath -Raw | ConvertFrom-Json
    $hostEntries = New-Object System.Collections.ArrayList
    $index = 0

    foreach ($item in @($items)) {
        $hostName = Get-StringField -Object $item -Name "name"
        $hostAddress = Get-StringField -Object $item -Name "host"

        [void]$hostEntries.Add([pscustomobject]@{
            Index = $index
            Name = $hostName
            Address = $hostAddress
        })

        $index += 1
    }

    return ,$hostEntries.ToArray()
}

function Get-PingSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$HostEntries,

        [Parameter(Mandatory = $true)]
        [hashtable]$PingResults,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $snapshot = New-Object System.Collections.ArrayList

    [System.Threading.Monitor]::Enter($Lock)
    try {
        foreach ($hostEntry in $HostEntries) {
            $key = [string]$hostEntry.Index
            $current = $PingResults[$key]

            if ($null -eq $current) { $current = [ordered]@{
                destination = $hostEntry.Name
                status = "error"
                rtt = $null
                succeededAt = $null
            } }

            [void]$snapshot.Add([ordered]@{
                destination = $current.destination
                status = $current.status
                rtt = $current.rtt
                succeededAt = $current.succeededAt
            })
        }
    } finally {
        [System.Threading.Monitor]::Exit($Lock)
    }

    return ,$snapshot.ToArray()
}

function Start-PingWorker {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$HostEntries,

        [Parameter(Mandatory = $true)]
        [hashtable]$PingResults,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [hashtable]$WorkerState,

        [int]$PollIntervalSeconds = 10
    )

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ImportPSModule(@($workerModulePath))

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace

    $null = $ps.AddCommand("Invoke-PingWorkerLoop")
    [void]$ps.AddArgument($HostEntries)
    [void]$ps.AddArgument($PingResults)
    [void]$ps.AddArgument($Lock)
    [void]$ps.AddArgument($WorkerState)
    [void]$ps.AddArgument($PollIntervalSeconds)

    $handle = $ps.BeginInvoke()

    return [pscustomobject]@{
        Runspace = $runspace
        PowerShell = $ps
        Handle = $handle
    }
}

function Stop-PingWorker {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Worker,

        [Parameter(Mandatory = $true)]
        [hashtable]$WorkerState
    )

    $WorkerState.Stop = $true

    if ($null -eq $Worker) { return }

    try {
        $null = $Worker.PowerShell.EndInvoke($Worker.Handle)
    } catch {
        if ($_.Exception.Message -notlike "*The pipeline has been stopped*") { Write-Host ("Ping worker stopped with error: {0}" -f $_.Exception.Message) }
    } finally {
        try { $Worker.PowerShell.Dispose() } catch { }
        try { $Worker.Runspace.Close() } catch { }
        try { $Worker.Runspace.Dispose() } catch { }
    }
}

function Invoke-StaticResourceRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -ne "GET") { return $false }

    $relativePath = switch ($path) {
        "/" { "index.html" }
        "/index.html" { "index.html" }
        "/script.js" { "script.js" }
        "/style.css" { "style.css" }
        default { $null }
    }

    if ($null -eq $relativePath) { return $false }

    $filePath = Join-Path $AppRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath)) { Send-TextResponse -Response $response -Text "Missing file" -StatusCode 500; return $true }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    Send-BytesResponse -Response $response -Bytes $bytes -ContentType (Get-ContentType -Path $filePath)
    return $true
}

$appRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($appRoot)) { $appRoot = (Get-Location).Path }

$workerModulePath = Join-Path $appRoot "ping-worker.psm1"
Import-Module $workerModulePath -Force

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:9000/")
$hostsPath = Join-Path $appRoot "hosts.json"
$hostEntries = Import-Hosts -HostsPath $hostsPath
$pingResults = [hashtable]::Synchronized(@{})
$lock = New-Object Object
$workerState = [hashtable]::Synchronized(@{ Stop = $false })
$worker = $null

Invoke-PingSweep -HostEntries $hostEntries -PingResults $pingResults -Lock $lock
$worker = Start-PingWorker -HostEntries $hostEntries -PingResults $pingResults -Lock $lock -WorkerState $workerState -PollIntervalSeconds 10

$listener.Start()
Write-Host "Ping server running at http://localhost:9000/"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod.ToUpperInvariant()

        try {
            if ($method -eq "GET" -and $path -eq "/pings") { Send-JsonResponse -Response $response -Payload (Get-PingSnapshot -HostEntries $hostEntries -PingResults $pingResults -Lock $lock); continue }
            if (Invoke-StaticResourceRoute -Context $context -AppRoot $appRoot) { continue }

            Send-TextResponse -Response $response -Text "Not Found" -StatusCode 404
        } catch {
            Write-Host ("Request failed: {0}" -f $_.Exception.Message)
            Send-InternalServerError -Response $response
        }
    }
} finally {
    Stop-PingWorker -Worker $worker -WorkerState $workerState

    if ($listener.IsListening) { $listener.Stop() }

    $listener.Close()
}
