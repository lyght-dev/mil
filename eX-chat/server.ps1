function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function New-JsonBytes {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    return [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 4))
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
    $Response.ContentLength64 = $Bytes.Length
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

function Get-ClientLabel {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.IPAddress]$Address
    )

    $parts = $Address.ToString().Split(".")
    if ($parts.Length -lt 4) {
        return "unknown"
    }

    return "{0}.{1}" -f $parts[2], $parts[3]
}

function Broadcast-Json {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    $bytes = New-JsonBytes -Payload $Payload
    $segment = [System.ArraySegment[byte]]::new($bytes, 0, $bytes.Length)

    foreach ($client in @($State.Clients.ToArray())) {
        $socket = $client.Socket
        $label = $client.Label

        if ($socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            [void]$State.Clients.Remove($client)
            continue
        }

        try {
            Write-Host ("Sending to {0}. SocketState={1}" -f $label, $socket.State)
            [void]([System.Net.WebSockets.WebSocket]$socket).SendAsync(
                ([System.ArraySegment[byte]]$segment),
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
            Write-Host ("Sent to {0}. SocketState={1}" -f $label, $socket.State)
        } catch {
            Write-Host ("Send failed for {0}: {1}" -f $label, $_.Exception.Message)
            if ($_.Exception.InnerException) {
                Write-Host ("Inner: {0}" -f $_.Exception.InnerException.Message)
            }
            [void]$State.Clients.Remove($client)
            Close-ClientSocket -Socket $socket -Status "InternalServerError" -Description "send failed"
        }
    }
}

function Close-ClientSocket {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket,

        [string]$Status = "NormalClosure",

        [string]$Description = "bye"
    )

    try {
        if ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or $Socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
            [void]([System.Net.WebSockets.WebSocket]$Socket).CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::$Status,
                $Description,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        }
    } catch {
    }

    try {
        $Socket.Dispose()
    } catch {
    }
}

function Invoke-ClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State
    )

    $buffer = New-Object byte[] 4096
    $builder = New-Object System.Text.StringBuilder
    Write-Host ("Client handler start for {0}. SocketState={1}" -f $Label, $Socket.State)

    try {
        while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $segment = [System.ArraySegment[byte]]::new($buffer, 0, $buffer.Length)
            $result = ([System.Net.WebSockets.WebSocket]$Socket).ReceiveAsync($segment, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            Write-Host ("Receive for {0}: Type={1} Count={2} End={3} CloseStatus={4} CloseDesc={5}" -f $Label, $result.MessageType, $result.Count, $result.EndOfMessage, $result.CloseStatus, $result.CloseStatusDescription)

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                break
            }

            if ($result.MessageType -ne [System.Net.WebSockets.WebSocketMessageType]::Text) {
                [void]$builder.Clear()
                continue
            }

            if ($result.Count -gt 0) {
                [void]$builder.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
            }

            if (-not $result.EndOfMessage) {
                continue
            }

            $text = $builder.ToString()
            [void]$builder.Clear()

            Broadcast-Json -State $State -Payload @{
                type = "chat"
                sender = $Label
                text = $text
            }
        }
    } catch {
        Write-Host ("Client handler failed for {0}: {1}" -f $Label, $_.Exception.Message)
        if ($_.Exception.InnerException) {
            Write-Host ("Inner: {0}" -f $_.Exception.InnerException.Message)
        }
    } finally {
        Write-Host ("Client handler closing for {0}. SocketState={1}" -f $Label, $Socket.State)
        foreach ($client in @($State.Clients.ToArray())) {
            if ([object]::ReferenceEquals($client.Socket, $Socket)) {
                [void]$State.Clients.Remove($client)
                break
            }
        }

        Broadcast-Json -State $State -Payload @{
            type = "system"
            text = "$Label left"
        }

        Close-ClientSocket -Socket $Socket
    }
}

function Start-ChatClient {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers
    )

    $subProtocol = [System.Management.Automation.Language.NullString]::Value
    $wsContext = $Context.AcceptWebSocketAsync($subProtocol).GetAwaiter().GetResult()
    $socket = $wsContext.WebSocket
    $label = Get-ClientLabel -Address $Context.Request.RemoteEndPoint.Address
    Write-Host ("Accepted client {0}. SocketState={1}" -f $label, $socket.State)

    $client = [hashtable]::Synchronized(@{
        Socket = $socket
        Label = $label
    })
    [void]$State.Clients.Add($client)

    Broadcast-Json -State $State -Payload @{
        type = "system"
        text = "$label joined"
    }
    Write-Host ("Joined broadcast handled for {0}. SocketState={1}" -f $label, $socket.State)

    $ps = [powershell]::Create()
    $ps.RunspacePool = $RunspacePool
    $null = $ps.AddCommand("Invoke-ClientHandler").AddArgument($socket).AddArgument($label).AddArgument($state)
    $null = $ps.BeginInvoke()
    [void]$Handlers.Add($ps)
}

function Start-EXChat {
    $appRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($appRoot)) {
        $appRoot = (Get-Location).Path
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:8888/")

    $state = [hashtable]::Synchronized(@{
        Clients = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    })

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "New-JsonBytes", (Get-Item function:New-JsonBytes).ScriptBlock.ToString()))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "Close-ClientSocket", (Get-Item function:Close-ClientSocket).ScriptBlock.ToString()))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "Broadcast-Json", (Get-Item function:Broadcast-Json).ScriptBlock.ToString()))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry "Invoke-ClientHandler", (Get-Item function:Invoke-ClientHandler).ScriptBlock.ToString()))

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 16, $iss, $Host)
    $runspacePool.Open()
    $handlers = New-Object System.Collections.ArrayList

    try {
        $listener.Start()
        Write-Host "eX-chat listening on http://+:8888/"

        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $path = $context.Request.Url.AbsolutePath

            if ($path -eq "/ws") {
                if (-not $context.Request.IsWebSocketRequest) {
                    Send-TextResponse -Response $context.Response -Text "WebSocket required" -StatusCode 400
                    continue
                }

                try {
                    Start-ChatClient -Context $context -State $state -RunspacePool $runspacePool -Handlers $handlers
                } catch {
                    Write-Host ("WebSocket accept failed: {0}" -f $_.Exception.Message)
                    if ($_.Exception.InnerException) {
                        Write-Host ("Inner: {0}" -f $_.Exception.InnerException.Message)
                    }
                    if ($context.Response.OutputStream.CanWrite) {
                        Send-TextResponse -Response $context.Response -Text "WebSocket accept failed" -StatusCode 500
                    }
                }

                continue
            }

            $relativePath = switch ($path) {
                "/" { "index.html" }
                "/index.html" { "index.html" }
                "/script.js" { "script.js" }
                "/style.css" { "style.css" }
                default { $null }
            }

            if ($null -eq $relativePath) {
                Send-TextResponse -Response $context.Response -Text "Not Found" -StatusCode 404
                continue
            }

            $filePath = Join-Path $appRoot $relativePath
            if (-not (Test-Path -LiteralPath $filePath)) {
                Send-TextResponse -Response $context.Response -Text "Missing file" -StatusCode 500
                continue
            }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            Send-BytesResponse -Response $context.Response -Bytes $bytes -ContentType (Get-ContentType -Path $filePath)
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

        foreach ($client in @($state.Clients.ToArray())) {
            Close-ClientSocket -Socket $client.Socket -Description "shutdown"
        }

        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Start-EXChat
}
