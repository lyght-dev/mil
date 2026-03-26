function Send-CaveBroadcast {
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
        foreach ($entry in @($Clients.ToArray())) {
            $socket = $entry.Socket
            if ($null -eq $socket) {
                continue
            }

            if ($socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                continue
            }

            try {
                $socket.SendAsync(
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

function Close-CaveSocket {
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

function Remove-CaveClient {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    [System.Threading.Monitor]::Enter($Lock)
    try {
        foreach ($entry in @($Clients.ToArray())) {
            if ($entry.Socket -ne $Socket) {
                continue
            }

            [void]$Clients.Remove($entry)
            break
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Lock)
    }
}

function Invoke-CaveClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$Clients,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $buffer = New-Object byte[] 2048

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

            if ($result.MessageType -ne [System.Net.WebSockets.WebSocketMessageType]::Text -or $result.Count -le 0) {
                continue
            }

            $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            Send-CaveBroadcast -Message $message -Clients $Clients -Lock $Lock
        }
    }
    catch {
        Write-Host ("Client handler failed: {0}" -f $_.Exception.Message)
        throw
    }
    finally {
        Remove-CaveClient -Socket $Socket -Clients $Clients -Lock $Lock
        Close-CaveSocket -Socket $Socket

        Send-CaveBroadcast -Message ((@{
                    type = "peer"
                    event = "leave"
                    role = $Role
                } | ConvertTo-Json -Compress)) -Clients $Clients -Lock $Lock
        Write-Host ("Client disconnected ({0})" -f $Role)
    }
}

Export-ModuleMember -Function Invoke-CaveClientHandler
