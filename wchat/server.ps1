Add-Type -AssemblyName System.Net.Http

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:8080/")
$listener.Start()

Write-Host "Web server running at http://localhost:8080/"
Write-Host "Open / in a browser. WebSocket endpoint is /ws"

$appRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($appRoot)) {
    $appRoot = (Get-Location).Path
}

$workerModulePath = Join-Path $appRoot "wchat-worker.psm1"
$clients = New-Object System.Collections.ArrayList
$lock = New-Object Object
$handlers = New-Object System.Collections.ArrayList

function SendHtml($response) {
    $filePath = Join-Path $appRoot "index.html"
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $response.StatusCode = 200
    $response.ContentType = "text/html; charset=utf-8"
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function SendText($response, $statusCode, $text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $response.StatusCode = $statusCode
    $response.ContentType = "text/plain; charset=utf-8"
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function RemoveClient($socket) {
    [System.Threading.Monitor]::Enter($lock)
    try { [void]$clients.Remove($socket) }
    finally { [System.Threading.Monitor]::Exit($lock) }
}

function CloseSocket($socket) {
    try {
        if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or $socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
            $socket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "Closing",
                [Threading.CancellationToken]::None
            ).Wait()
        }
    }
    catch { }
}

function CleanupHandlers() {
    foreach ($entry in @($handlers.ToArray())) {
        if (-not $entry.Handle.IsCompleted) {
            continue
        }

        try {
            $null = $entry.PowerShell.EndInvoke($entry.Handle)
        }
        catch {
            Write-Host ("Client handler failed: {0}" -f $_.Exception.Message)
        }
        finally {
            try {  $entry.PowerShell.Dispose() }
            catch { }

            try { $entry.Runspace.Close() }
            catch { }

            try { $entry.Runspace.Dispose() }
            catch { }

            [void]$handlers.Remove($entry)
        }
    }
}

function StopHandlers() {
    foreach ($entry in @($handlers.ToArray())) {
        try {
            if (-not $entry.Handle.IsCompleted) { $entry.PowerShell.Stop() }
        }
        catch { }

        try { $null = $entry.PowerShell.EndInvoke($entry.Handle) }
        catch {
            if ($_.Exception.Message -notlike '*The pipeline has been stopped.*') {
                Write-Host ("Client handler stop failed: {0}" -f $_.Exception.Message)
            }
        }
        finally {
            try { $entry.PowerShell.Dispose() }
            catch { }

            try { $entry.Runspace.Close() }
            catch { }

            try { $entry.Runspace.Dispose() }
            catch { }
        }
    }
}

function StartClientHandler($socket) {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ImportPSModule(@($workerModulePath))

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($Host, $iss)
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    try {
        $ps.Runspace = $runspace
        $null = $ps.AddCommand("Invoke-WChatClientHandler").AddArgument($socket).AddArgument($clients).AddArgument($lock)
        $handle = $ps.BeginInvoke()

        [void]$handlers.Add([pscustomobject]@{
            Runspace = $runspace
            PowerShell = $ps
            Handle = $handle
            Socket = $socket
        })
    }
    catch {
        try { $ps.Dispose() }
        catch { }

        try { $runspace.Close() }
        catch { }

        try { $runspace.Dispose() }
        catch { }

        throw
    }
}

try {
    while ($true) {
        CleanupHandlers

        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod.ToUpperInvariant()

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            SendHtml $context.Response
            continue
        }

        if ($path -ne "/ws" -and $path -ne "/ws/") {
            SendText $context.Response 404 "Not Found"
            continue
        }

        if (-not $context.Request.IsWebSocketRequest) {
            SendText $context.Response 400 "WebSocket required"
            continue
        }

        try {
            $wsContext = $context.AcceptWebSocketAsync([System.Management.Automation.Language.NullString]::Value).Result
            $ws = $wsContext.WebSocket

            [System.Threading.Monitor]::Enter($lock)
            try {
                $clients.Add($ws) | Out-Null
                Write-Host "Client connected: $($clients.Count)"
            }
            finally {
                [System.Threading.Monitor]::Exit($lock)
            }

            try {
                StartClientHandler $ws
            }
            catch {
                Write-Host ("Client handler start failed: {0}" -f $_.Exception.Message)
                RemoveClient $ws
                CloseSocket $ws
            }
        }
        catch {
            Write-Host "Connection error: $_"
        }
    }
}
finally {
    StopHandlers

    foreach ($socket in @($clients.ToArray())) {
        CloseSocket $socket
    }

    if ($listener.IsListening) { $listener.Stop() }

    $listener.Close()
}
