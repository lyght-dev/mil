Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Net.Http

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

function Broadcast {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = [System.ArraySegment[byte]]::new($bytes, 0, $bytes.Length)

    [System.Threading.Monitor]::Enter($Lock)
    try {
        foreach ($client in @($Clients.ToArray())) {
            if ($client.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                continue
            }

            try {
                $client.SendAsync(
                    $segment,
                    [System.Net.WebSockets.WebSocketMessageType]::Text,
                    $true,
                    [System.Threading.CancellationToken]::None
                ).GetAwaiter().GetResult()
            } catch {
            }
        }
    } finally {
        [System.Threading.Monitor]::Exit($Lock)
    }
}

function Invoke-ClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $buffer = New-Object byte[] 1024

    try {
        while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $segment = [System.ArraySegment[byte]]::new($buffer, 0, $buffer.Length)
            $result = $Socket.ReceiveAsync(
                $segment,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                $Socket.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                    "Closing",
                    [System.Threading.CancellationToken]::None
                ).GetAwaiter().GetResult()
                break
            }

            $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            Write-Host ("Received: {0}" -f $message)
            Broadcast -Message $message -Clients $Clients -Lock $Lock
        }
    } catch {
    } finally {
        [System.Threading.Monitor]::Enter($Lock)
        try {
            [void]$Clients.Remove($Socket)
        } finally {
            [System.Threading.Monitor]::Exit($Lock)
        }

        Write-Host "Client disconnected"
    }
}

$appRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($appRoot)) {
    $appRoot = (Get-Location).Path
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:8080/")

$clients = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$lock = [object]::new()
$handlers = [System.Collections.ArrayList]::new()

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "Broadcast", (Get-Item function:Broadcast).ScriptBlock.ToString()))
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "Invoke-ClientHandler", (Get-Item function:Invoke-ClientHandler).ScriptBlock.ToString()))
$runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 8, $iss, $Host)
$runspacePool.Open()

$listener.Start()

Write-Host "Web server running at http://localhost:8080/"
Write-Host "Open / in a browser. WebSocket endpoint is /ws"

$nullString = [System.Management.Automation.Language.NullString]::Value

try {
    while ($true) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod.ToUpperInvariant()

        if ($path -eq "/ws" -or $path -eq "/ws/") {
            if (-not $context.Request.IsWebSocketRequest) {
                Send-TextResponse -Response $context.Response -Text "WebSocket required" -StatusCode 400
                continue
            }

            try {
                $wsContext = $context.AcceptWebSocketAsync($nullString).GetAwaiter().GetResult()
                $socket = $wsContext.WebSocket

                [System.Threading.Monitor]::Enter($lock)
                try {
                    [void]$clients.Add($socket)
                    Write-Host ("Client connected: {0}" -f $clients.Count)
                } finally {
                    [System.Threading.Monitor]::Exit($lock)
                }

                $ps = [powershell]::Create()
                $ps.RunspacePool = $runspacePool
                $null = $ps.AddCommand("Invoke-ClientHandler").AddArgument($socket).AddArgument($clients).AddArgument($lock)
                $null = $ps.BeginInvoke()
                [void]$handlers.Add($ps)
            } catch {
                Write-Host ("Connection error: {0}" -f $_.Exception.Message)
                if ($context.Response.OutputStream.CanWrite) {
                    Send-TextResponse -Response $context.Response -Text "WebSocket accept failed" -StatusCode 500
                }
            }

            continue
        }

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            $filePath = Join-Path $appRoot "index.html"
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            Send-BytesResponse -Response $context.Response -Bytes $bytes -ContentType "text/html; charset=utf-8"
            continue
        }

        Send-TextResponse -Response $context.Response -Text "Not Found" -StatusCode 404
    }
} finally {
    foreach ($handler in @($handlers)) {
        try {
            $handler.Stop()
        } catch {
        }

        try {
            $handler.Dispose()
        } catch {
        }
    }

    foreach ($client in @($clients.ToArray())) {
        try {
            if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open -or $client.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
                $client.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                    "Closing",
                    [System.Threading.CancellationToken]::None
                ).GetAwaiter().GetResult()
            }
        } catch {
        }
    }

    if ($listener.IsListening) {
        $listener.Stop()
    }

    $listener.Close()
    $runspacePool.Close()
    $runspacePool.Dispose()
}
