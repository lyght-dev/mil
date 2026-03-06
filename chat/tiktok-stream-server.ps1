[CmdletBinding()]
param(
    [int]$Port = 9997,
    [string]$BindAddress = "localhost",
    [int]$HeartbeatSec = 15,
    [int]$MaxWorkers = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Remove-ClosedStreams {
    param([hashtable]$State)

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        for ($i = $State.Streams.Count - 1; $i -ge 0; $i--) {
            if ($State.Streams[$i].Closed) {
                $State.Streams.RemoveAt($i)
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Cleanup-CompletedRequests {
    param([System.Collections.ArrayList]$ActiveRequests)

    for ($i = $ActiveRequests.Count - 1; $i -ge 0; $i--) {
        $entry = $ActiveRequests[$i]
        if (-not $entry.Handle.IsCompleted) {
            continue
        }

        try {
            $entry.PowerShell.EndInvoke($entry.Handle)
        }
        catch {
        }
        finally {
            $entry.PowerShell.Dispose()
            $ActiveRequests.RemoveAt($i)
        }
    }
}

$state = [hashtable]::Synchronized(@{
    Lock    = New-Object object
    Streams = New-Object System.Collections.ArrayList
    Running = $true
})

$settings = [hashtable]::Synchronized(@{
    HeartbeatSec = $HeartbeatSec
})

$handlerScript = {
    param(
        [System.Net.HttpListenerContext]$Context,
        [hashtable]$State,
        [hashtable]$Settings
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    function Add-Cors {
        param([System.Net.HttpListenerResponse]$Response)

        $Response.Headers["Access-Control-Allow-Origin"] = "*"
        $Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        $Response.Headers["Access-Control-Allow-Headers"] = "Content-Type"
    }

    function Close-Response {
        param([System.Net.HttpListenerResponse]$Response)

        try {
            $Response.OutputStream.Close()
        }
        catch {
        }

        try {
            $Response.Close()
        }
        catch {
        }
    }

    function Send-PlainText {
        param(
            [System.Net.HttpListenerContext]$Ctx,
            [int]$StatusCode,
            [string]$Text
        )

        $response = $Ctx.Response
        $response.StatusCode = $StatusCode
        $response.ContentType = "text/plain; charset=utf-8"
        $response.ContentEncoding = [System.Text.Encoding]::UTF8
        Add-Cors -Response $response

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        Close-Response -Response $response
    }

    function Write-SseFrame {
        param(
            [object]$StreamClient,
            [string]$Frame
        )

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Frame)
        [System.Threading.Monitor]::Enter($StreamClient.Lock)
        try {
            if ($StreamClient.Closed) {
                return $false
            }

            $StreamClient.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $StreamClient.Response.OutputStream.Flush()
            return $true
        }
        catch {
            $StreamClient.Closed = $true
            return $false
        }
        finally {
            [System.Threading.Monitor]::Exit($StreamClient.Lock)
        }
    }

    try {
        $request = $Context.Request
        $path = $request.Url.AbsolutePath.ToLowerInvariant()
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($method -eq "OPTIONS") {
            $Context.Response.StatusCode = 204
            Add-Cors -Response $Context.Response
            $Context.Response.ContentLength64 = 0
            Close-Response -Response $Context.Response
            return
        }

        if ($method -eq "GET" -and $path -eq "/stream") {
            $response = $Context.Response
            $response.StatusCode = 200
            $response.SendChunked = $true
            $response.KeepAlive = $true
            $response.ContentType = "text/event-stream; charset=utf-8"
            $response.ContentEncoding = [System.Text.Encoding]::UTF8
            $response.Headers["Cache-Control"] = "no-cache"
            Add-Cors -Response $response

            $client = [pscustomobject]@{
                Response = $response
                Lock     = New-Object object
                Closed   = $false
            }

            [System.Threading.Monitor]::Enter($State.Lock)
            try {
                [void]$State.Streams.Add($client)
            }
            finally {
                [System.Threading.Monitor]::Exit($State.Lock)
            }

            $null = Write-SseFrame -StreamClient $client -Frame ": connected`n`n"

            while ($State.Running -and -not $client.Closed) {
                Start-Sleep -Seconds $Settings.HeartbeatSec
                $null = Write-SseFrame -StreamClient $client -Frame ": keepalive`n`n"
            }

            $client.Closed = $true
            Close-Response -Response $response
            return
        }

        if ($method -eq "POST" -and $path -eq "/tick") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            try {
                $body = $reader.ReadToEnd()
            }
            finally {
                $reader.Close()
            }

            if ([string]$body -ne "tick") {
                Send-PlainText -Ctx $Context -StatusCode 400 -Text "send tick"
                return
            }

            [System.Threading.Monitor]::Enter($State.Lock)
            try {
                $targets = @($State.Streams)
            }
            finally {
                [System.Threading.Monitor]::Exit($State.Lock)
            }

            $delivered = 0
            foreach ($client in $targets) {
                if (Write-SseFrame -StreamClient $client -Frame "event: tock`ndata: tock`n`n") {
                    $delivered++
                }
            }

            Send-PlainText -Ctx $Context -StatusCode 200 -Text ("tock ({0})" -f $delivered)
            return
        }

        if ($method -eq "GET" -and $path -eq "/health") {
            Send-PlainText -Ctx $Context -StatusCode 200 -Text "ok"
            return
        }

        Send-PlainText -Ctx $Context -StatusCode 404 -Text "not found"
    }
    catch {
        try {
            Send-PlainText -Ctx $Context -StatusCode 500 -Text $_.Exception.Message
        }
        catch {
        }
    }
}

$listener = $null
$pool = $null
$activeRequests = New-Object System.Collections.ArrayList

try {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add(("http://{0}:{1}/" -f $BindAddress, $Port))
    $listener.Start()

    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxWorkers)
    $pool.Open()

    [Console]::WriteLine(("tiktok SSE server listening on http://{0}:{1}" -f $BindAddress, $Port))
    [Console]::WriteLine("GET /stream")
    [Console]::WriteLine("POST /tick with body: tick")

    while ($listener.IsListening) {
        $pending = $listener.BeginGetContext($null, $null)
        while (-not $pending.AsyncWaitHandle.WaitOne(1000)) {
            Cleanup-CompletedRequests -ActiveRequests $activeRequests
            Remove-ClosedStreams -State $state
        }

        $context = $listener.EndGetContext($pending)
        Cleanup-CompletedRequests -ActiveRequests $activeRequests
        Remove-ClosedStreams -State $state

        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript($handlerScript).AddArgument($context).AddArgument($state).AddArgument($settings)
        $handle = $ps.BeginInvoke()
        [void]$activeRequests.Add([pscustomobject]@{
            PowerShell = $ps
            Handle     = $handle
        })
    }
}
catch {
    [Console]::Error.WriteLine(("server error: {0}" -f $_.Exception.Message))
    throw
}
finally {
    $state.Running = $false

    if ($null -ne $listener) {
        try {
            if ($listener.IsListening) {
                $listener.Stop()
            }
        }
        catch {
        }

        try {
            $listener.Close()
        }
        catch {
        }
    }

    Cleanup-CompletedRequests -ActiveRequests $activeRequests
    foreach ($entry in @($activeRequests)) {
        try {
            $entry.PowerShell.EndInvoke($entry.Handle)
        }
        catch {
        }
        finally {
            $entry.PowerShell.Dispose()
        }
    }

    if ($null -ne $pool) {
        try {
            $pool.Close()
        }
        catch {
        }
        finally {
            $pool.Dispose()
        }
    }
}
