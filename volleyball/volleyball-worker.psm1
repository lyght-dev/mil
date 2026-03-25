function ConvertTo-VolleyBoolean {
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = [string]$Value
    if ($text -eq "") { return $false }

    return ($text -eq "true" -or $text -eq "1")
}

function Get-VolleyPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Close-VolleyWorkerSocket {
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

function Invoke-VolleyballClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

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

            $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            $payload = $null

            try {
                $payload = $text | ConvertFrom-Json
            }
            catch {
                continue
            }

            if ($null -eq $payload) { continue }

            $messageType = [string](Get-VolleyPropertyValue -Object $payload -Name "type")
            if ($messageType -ne "input") { continue }

            $left = ConvertTo-VolleyBoolean -Value (Get-VolleyPropertyValue -Object $payload -Name "left")
            $right = ConvertTo-VolleyBoolean -Value (Get-VolleyPropertyValue -Object $payload -Name "right")
            $jump = ConvertTo-VolleyBoolean -Value (Get-VolleyPropertyValue -Object $payload -Name "jump")

            [System.Threading.Monitor]::Enter($Lock)
            try {
                $players = $RoomState.Players
                $slot = $players[$Role]
                if ($null -eq $slot -or $slot.Socket -ne $Socket) {
                    continue
                }

                $input = $slot.Input
                $input.left = $left
                $input.right = $right
                $input.jump = $jump
            }
            finally {
                [System.Threading.Monitor]::Exit($Lock)
            }
        }
    }
    catch {
        Write-Host ("Client handler failed: {0}" -f $_.Exception.Message)
    }
    finally {
        [System.Threading.Monitor]::Enter($Lock)
        try {
            $players = $RoomState.Players
            $slot = $players[$Role]

            if ($null -ne $slot -and $slot.Socket -eq $Socket) {
                $players[$Role] = $null
                [void]$RoomState.PendingEvents.Add([ordered]@{
                    name = "peer_left"
                    side = $Role
                })
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($Lock)
        }

        Close-VolleyWorkerSocket -Socket $Socket
        Write-Host ("Client disconnected: {0}" -f $Role)
    }
}

Export-ModuleMember -Function Invoke-VolleyballClientHandler
