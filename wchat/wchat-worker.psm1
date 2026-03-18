function Send-WChatBroadcast {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

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
                    [Threading.CancellationToken]::None
                ).GetAwaiter().GetResult()
            }
            catch {
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Lock)
    }
}

function Close-WChatSocket {
    param(
        [Parameter(Mandatory = $true)]
        $Socket
    )

    try {
        if ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or $Socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
            $Socket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "Closing",
                [Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        }
    }
    catch {
    }
}

function Invoke-WChatClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $buffer = New-Object byte[] 1024

    try {
        while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $buffer)
            $result = $Socket.ReceiveAsync(
                $segment,
                [Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                break
            }

            $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            Send-WChatBroadcast -Message $message -Clients $Clients -Lock $Lock
        }
    }
    catch {
        Write-Host ("Client handler failed: {0}" -f $_.Exception.Message)
        throw
    }
    finally {
        [System.Threading.Monitor]::Enter($Lock)
        try {
            [void]$Clients.Remove($Socket)
        }
        finally {
            [System.Threading.Monitor]::Exit($Lock)
        }

        Close-WChatSocket -Socket $Socket
        Write-Host "Client disconnected"
    }
}

Export-ModuleMember -Function Invoke-WChatClientHandler
