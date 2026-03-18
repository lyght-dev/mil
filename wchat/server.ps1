Add-Type -AssemblyName System.Net.Http

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/ws/")
$listener.Start()

Write-Host "WebSocket Server running at ws://localhost:8080/ws/"

$nullString = [System.Management.Automation.Language.NullString]::Value

$clients = New-Object System.Collections.ArrayList
$lock = New-Object Object

function Broadcast($message) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

    [System.Threading.Monitor]::Enter($lock)
    try {
        foreach ($client in $clients.ToArray()) {
            if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                try {
                    $client.SendAsync(
                        $segment,
                        [System.Net.WebSockets.WebSocketMessageType]::Text,
                        $true,
                        [Threading.CancellationToken]::None
                    ).Wait()
                } catch {}
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($lock)
    }
}

function HandleClient($ws) {
    $socket = $ws

    [System.Threading.Tasks.Task]::Run(
        [System.Action]{

            $buffer = New-Object byte[] 1024

            while ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                try {
                    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $buffer)
                    $result = $socket.ReceiveAsync(
                        $segment,
                        [Threading.CancellationToken]::None
                    ).Result

                    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        $socket.CloseAsync(
                            [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                            "Closing",
                            [Threading.CancellationToken]::None
                        ).Wait()
                        break
                    }

                    $msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
                    Write-Host "Received: $msg"

                    Broadcast $msg
                }
                catch {
                    break
                }
            }

            # 클라이언트 제거
            [System.Threading.Monitor]::Enter($lock)
            try {
                $clients.Remove($socket)
            }
            finally {
                [System.Threading.Monitor]::Exit($lock)
            }

            Write-Host "Client disconnected"
        }
    ) | Out-Null
}

while ($true) {
    $context = $listener.GetContext()

    if (-not $context.Request.IsWebSocketRequest) {
        $context.Response.StatusCode = 400
        $context.Response.Close()
        continue
    }

    try {
        $wsContext = $context.AcceptWebSocketAsync($nullString).Result
        $ws = $wsContext.WebSocket

        [System.Threading.Monitor]::Enter($lock)
        try {
            $clients.Add($ws) | Out-Null
            Write-Host "Client connected: $($clients.Count)"
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }

        HandleClient $ws
    }
    catch {
        Write-Host "Connection error: $_"
    }
}