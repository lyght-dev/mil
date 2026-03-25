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

function Send-InternalServerError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    try {
        if ($Response.OutputStream.CanWrite) {
            Send-TextResponse -Response $Response -Text "internal server error" -StatusCode 500
        }
    }
    catch {
    }
}

function Close-VolleySocket {
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

function Send-VolleyMessage {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    if ($Socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        return $false
    }

    $text = $Payload | ConvertTo-Json -Compress -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

    try {
        $Socket.SendAsync(
            $segment,
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()
        return $true
    }
    catch {
        return $false
    }
}

function Clamp-Value {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Value,

        [Parameter(Mandatory = $true)]
        [double]$Min,

        [Parameter(Mandatory = $true)]
        [double]$Max
    )

    return [Math]::Max($Min, [Math]::Min($Value, $Max))
}

function Initialize-RoomState {
    $world = @{
        width = 960.0
        height = 540.0
        groundY = 500.0
        net = @{
            x = 480.0
            width = 20.0
            height = 120.0
        }
        player = @{
            width = 48.0
            height = 60.0
        }
        ballRadius = 14.0
    }

    return [hashtable]::Synchronized(@{
        world = $world
        phase = "waiting"
        round = 0
        players = @{
            left = $null
            right = $null
        }
        pendingEvents = New-Object System.Collections.ArrayList
        lastBroadcastInputs = @{
            left = @{
                left = $false
                right = $false
                jump = $false
            }
            right = @{
                left = $false
                right = $false
                jump = $false
            }
        }
        leftBody = @{
            x = 180.0
            y = 440.0
            vx = 0.0
            vy = 0.0
            onGround = $true
        }
        rightBody = @{
            x = 732.0
            y = 440.0
            vx = 0.0
            vy = 0.0
            onGround = $true
        }
        ball = @{
            x = 480.0
            y = 220.0
            vx = 0.0
            vy = 0.0
        }
    })
}

function Add-PendingEvent {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Winner,

        [string]$Side
    )

    $item = [ordered]@{
        name = $Name
    }

    if (-not [string]::IsNullOrWhiteSpace($Winner)) {
        $item.winner = $Winner
    }

    if (-not [string]::IsNullOrWhiteSpace($Side)) {
        $item.side = $Side
    }

    [void]$RoomState.pendingEvents.Add($item)
}

function Reset-Round {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState
    )

    $world = $RoomState.world
    $playerWidth = [double]$world.player.width
    $playerHeight = [double]$world.player.height
    $groundY = [double]$world.groundY
    $width = [double]$world.width
    $netX = [double]$world.net.x

    $leftBody = $RoomState.leftBody
    $leftBody.x = 180.0
    $leftBody.y = $groundY - $playerHeight
    $leftBody.vx = 0.0
    $leftBody.vy = 0.0
    $leftBody.onGround = $true

    $rightBody = $RoomState.rightBody
    $rightBody.x = $width - 180.0 - $playerWidth
    $rightBody.y = $groundY - $playerHeight
    $rightBody.vx = 0.0
    $rightBody.vy = 0.0
    $rightBody.onGround = $true

    $ball = $RoomState.ball
    $ball.x = $netX
    $ball.y = 220.0
    $direction = if (($RoomState.round % 2) -eq 0) { 1.0 } else { -1.0 }
    $ball.vx = 4.0 * $direction
    $ball.vy = -6.0
}

function Get-InputFlag {
    param(
        [Parameter(Mandatory = $false)]
        $InputState,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputState) {
        return $false
    }

    $target = $InputState
    if ($target -is [System.Array]) {
        if ($target.Count -le 0) {
            return $false
        }

        $target = $target[0]
    }

    if ($target -is [hashtable]) {
        if (-not $target.ContainsKey($Name)) {
            return $false
        }

        return [bool]$target[$Name]
    }

    $property = $target.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $false
    }

    return [bool]$property.Value
}

function Move-PlayerBody {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Body,

        [Parameter(Mandatory = $true)]
        $Input,

        [Parameter(Mandatory = $true)]
        [double]$MinX,

        [Parameter(Mandatory = $true)]
        [double]$MaxX,

        [Parameter(Mandatory = $true)]
        [double]$GroundY,

        [Parameter(Mandatory = $true)]
        [double]$PlayerHeight
    )

    $gravity = 0.75
    $speed = 7.0
    $jumpSpeed = -13.0

    $dir = 0.0
    if (Get-InputFlag -InputState $Input -Name "left") { $dir -= 1.0 }
    if (Get-InputFlag -InputState $Input -Name "right") { $dir += 1.0 }

    $Body.vx = $dir * $speed

    if ((Get-InputFlag -InputState $Input -Name "jump") -and [bool]$Body.onGround) {
        $Body.vy = $jumpSpeed
        $Body.onGround = $false
    }

    $Body.vy += $gravity

    $Body.x += $Body.vx
    $Body.y += $Body.vy

    $Body.x = Clamp-Value -Value ([double]$Body.x) -Min $MinX -Max $MaxX

    $floor = $GroundY - $PlayerHeight
    if ($Body.y -ge $floor) {
        $Body.y = $floor
        $Body.vy = 0.0
        $Body.onGround = $true
    }
    else {
        $Body.onGround = $false
    }

    if ($Body.y -lt 0.0) {
        $Body.y = 0.0
        if ($Body.vy -lt 0.0) {
            $Body.vy = 0.0
        }
    }
}

function Resolve-BallRectCollision {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Ball,

        [Parameter(Mandatory = $true)]
        [double]$RectX,

        [Parameter(Mandatory = $true)]
        [double]$RectY,

        [Parameter(Mandatory = $true)]
        [double]$RectWidth,

        [Parameter(Mandatory = $true)]
        [double]$RectHeight,

        [Parameter(Mandatory = $true)]
        [double]$Radius,

        [Parameter(Mandatory = $true)]
        [double]$Restitution,

        [double]$CarryX = 0.0,

        [double]$CarryY = 0.0
    )

    $nearestX = Clamp-Value -Value ([double]$Ball.x) -Min $RectX -Max ($RectX + $RectWidth)
    $nearestY = Clamp-Value -Value ([double]$Ball.y) -Min $RectY -Max ($RectY + $RectHeight)

    $dx = [double]$Ball.x - $nearestX
    $dy = [double]$Ball.y - $nearestY
    $distSquared = ($dx * $dx) + ($dy * $dy)
    $radiusSquared = $Radius * $Radius

    if ($distSquared -ge $radiusSquared) {
        return
    }

    $nx = 0.0
    $ny = 0.0
    $distance = 0.0

    if ($distSquared -lt 0.0001) {
        $centerX = $RectX + ($RectWidth / 2.0)
        $centerY = $RectY + ($RectHeight / 2.0)
        $centerDx = [double]$Ball.x - $centerX
        $centerDy = [double]$Ball.y - $centerY

        if ([Math]::Abs($centerDx) -ge [Math]::Abs($centerDy)) {
            $nx = if ($centerDx -ge 0.0) { 1.0 } else { -1.0 }
            $ny = 0.0
        }
        else {
            $nx = 0.0
            $ny = if ($centerDy -ge 0.0) { 1.0 } else { -1.0 }
        }
    }
    else {
        $distance = [Math]::Sqrt($distSquared)
        $nx = $dx / $distance
        $ny = $dy / $distance
    }

    $penetration = $Radius - $distance
    $Ball.x += $nx * $penetration
    $Ball.y += $ny * $penetration

    $approachVelocity = ($Ball.vx * $nx) + ($Ball.vy * $ny)
    if ($approachVelocity -lt 0.0) {
        $impulse = -(1.0 + $Restitution) * $approachVelocity
        $Ball.vx += $impulse * $nx
        $Ball.vy += $impulse * $ny
    }

    $Ball.vx += $CarryX
    $Ball.vy += $CarryY
}

function Sanitize-ClosedSlots {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState
    )

    foreach ($role in @("left", "right")) {
        $slot = $RoomState.players[$role]
        if ($null -eq $slot) {
            continue
        }

        if ($slot.Socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            $RoomState.players[$role] = $null
            Add-PendingEvent -RoomState $RoomState -Name "peer_left" -Side $role
        }
    }
}

function Invoke-GameTick {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    [System.Threading.Monitor]::Enter($Lock)
    try {
        Sanitize-ClosedSlots -RoomState $RoomState

        $world = $RoomState.world
        $players = $RoomState.players
        $leftConnected = $null -ne $players["left"]
        $rightConnected = $null -ne $players["right"]
        $playerWidth = [double]$world.player.width
        $playerHeight = [double]$world.player.height
        $groundY = [double]$world.groundY
        $width = [double]$world.width
        $netX = [double]$world.net.x
        $netWidth = [double]$world.net.width
        $netHeight = [double]$world.net.height
        $radius = [double]$world.ballRadius

        if (-not ($leftConnected -and $rightConnected)) {
            $RoomState.phase = "waiting"
            Reset-Round -RoomState $RoomState
            $RoomState.ball.vx = 0.0
            $RoomState.ball.vy = 0.0
        }
        else {
            if ($RoomState.phase -ne "playing") {
                $RoomState.phase = "playing"
                $RoomState.round = [int]$RoomState.round + 1
                Reset-Round -RoomState $RoomState
            }

            $leftInput = $players["left"]["input"]
            $rightInput = $players["right"]["input"]
            Move-PlayerBody -Body $RoomState.leftBody -Input $leftInput -MinX 0.0 -MaxX ($netX - ($netWidth / 2.0) - $playerWidth) -GroundY $groundY -PlayerHeight $playerHeight
            Move-PlayerBody -Body $RoomState.rightBody -Input $rightInput -MinX ($netX + ($netWidth / 2.0)) -MaxX ($width - $playerWidth) -GroundY $groundY -PlayerHeight $playerHeight

            $ball = $RoomState.ball
            $ball.vy += 0.5
            $ball.x += $ball.vx
            $ball.y += $ball.vy

            if (($ball.x - $radius) -lt 0.0) {
                $ball.x = $radius
                $ball.vx = [Math]::Abs([double]$ball.vx) * 0.95
            }

            if (($ball.x + $radius) -gt $width) {
                $ball.x = $width - $radius
                $ball.vx = -[Math]::Abs([double]$ball.vx) * 0.95
            }

            if (($ball.y - $radius) -lt 0.0) {
                $ball.y = $radius
                $ball.vy = [Math]::Abs([double]$ball.vy) * 0.95
            }

            $netLeft = $netX - ($netWidth / 2.0)
            $netTop = $groundY - $netHeight
            Resolve-BallRectCollision -Ball $ball -RectX $netLeft -RectY $netTop -RectWidth $netWidth -RectHeight $netHeight -Radius $radius -Restitution 0.9

            Resolve-BallRectCollision `
                -Ball $ball `
                -RectX ([double]$RoomState.leftBody.x) `
                -RectY ([double]$RoomState.leftBody.y) `
                -RectWidth $playerWidth `
                -RectHeight $playerHeight `
                -Radius $radius `
                -Restitution 0.95 `
                -CarryX (([double]$RoomState.leftBody.vx) * 0.2) `
                -CarryY (([Math]::Min([double]$RoomState.leftBody.vy, 0.0)) * 0.1)

            Resolve-BallRectCollision `
                -Ball $ball `
                -RectX ([double]$RoomState.rightBody.x) `
                -RectY ([double]$RoomState.rightBody.y) `
                -RectWidth $playerWidth `
                -RectHeight $playerHeight `
                -Radius $radius `
                -Restitution 0.95 `
                -CarryX (([double]$RoomState.rightBody.vx) * 0.2) `
                -CarryY (([Math]::Min([double]$RoomState.rightBody.vy, 0.0)) * 0.1)

            $ball.vx = Clamp-Value -Value ([double]$ball.vx) -Min -18.0 -Max 18.0
            $ball.vy = Clamp-Value -Value ([double]$ball.vy) -Min -18.0 -Max 18.0

            if (($ball.y + $radius) -ge $groundY) {
                $winner = if ([double]$ball.x -lt $netX) { "right" } else { "left" }
                Add-PendingEvent -RoomState $RoomState -Name "round_reset" -Winner $winner
                $RoomState.round = [int]$RoomState.round + 1
                Reset-Round -RoomState $RoomState
            }
        }

        foreach ($role in @("left", "right")) {
            $slot = $players[$role]
            if ($null -eq $slot) { continue }

            $currentInput = $slot["input"]
            $left = Get-InputFlag -InputState $currentInput -Name "left"
            $right = Get-InputFlag -InputState $currentInput -Name "right"
            $jump = Get-InputFlag -InputState $currentInput -Name "jump"
            $last = $RoomState.lastBroadcastInputs[$role]

            if ($left -eq [bool]$last.left -and $right -eq [bool]$last.right -and $jump -eq [bool]$last.jump) {
                continue
            }

            $last.left = $left
            $last.right = $right
            $last.jump = $jump

            $payload = [ordered]@{
                type = "input_update"
                role = $role
                left = $left
                right = $right
                jump = $jump
            }

            foreach ($targetRole in @("left", "right")) {
                $targetSlot = $players[$targetRole]
                if ($null -eq $targetSlot) { continue }
                [void](Send-VolleyMessage -Socket $targetSlot.Socket -Payload $payload)
            }
        }

        if ($RoomState.pendingEvents.Count -gt 0) {
            $events = @($RoomState.pendingEvents.ToArray())
            $RoomState.pendingEvents.Clear()

            foreach ($eventItem in $events) {
                $payload = [ordered]@{
                    type = "event"
                    name = [string]$eventItem.name
                }

                $winnerProperty = $eventItem.PSObject.Properties["winner"]
                if ($null -ne $winnerProperty -and -not [string]::IsNullOrWhiteSpace([string]$winnerProperty.Value)) {
                    $payload.winner = [string]$winnerProperty.Value
                }

                $sideProperty = $eventItem.PSObject.Properties["side"]
                if ($null -ne $sideProperty -and -not [string]::IsNullOrWhiteSpace([string]$sideProperty.Value)) {
                    $payload.side = [string]$sideProperty.Value
                }

                foreach ($role in @("left", "right")) {
                    $slot = $players[$role]
                    if ($null -eq $slot) { continue }
                    [void](Send-VolleyMessage -Socket $slot.Socket -Payload $payload)
                }
            }
        }

    }
    finally {
        [System.Threading.Monitor]::Exit($Lock)
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

    if ($method -ne "GET") {
        return $false
    }

    $relativePath = switch ($path) {
        "/" { "index.html" }
        "/index.html" { "index.html" }
        "/script.js" { "script.js" }
        "/style.css" { "style.css" }
        default { $null }
    }

    if ($null -eq $relativePath) {
        return $false
    }

    $filePath = Join-Path $AppRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath)) {
        Send-TextResponse -Response $response -Text "Missing file" -StatusCode 500
        return $true
    }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    Send-BytesResponse -Response $response -Bytes $bytes -ContentType (Get-ContentType -Path $filePath)
    return $true
}

function Get-AvailableRole {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState
    )

    foreach ($role in @("left", "right")) {
        if ($null -eq $RoomState.players[$role]) {
            return $role
        }
    }

    return $null
}

function Remove-PlayerBySocket {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        $Socket
    )

    foreach ($role in @("left", "right")) {
        $slot = $RoomState.players[$role]
        if ($null -eq $slot) { continue }
        if ($slot.Socket -eq $Socket) {
            $RoomState.players[$role] = $null
            Add-PendingEvent -RoomState $RoomState -Name "peer_left" -Side $role
        }
    }
}

function Start-ClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers,

        [Parameter(Mandatory = $true)]
        [string]$WorkerModulePath
    )

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ImportPSModule(@($WorkerModulePath))

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($Host, $iss)
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()

    try {
        $ps.Runspace = $runspace
        $null = $ps.AddCommand("Invoke-VolleyballClientHandler").AddArgument($Socket).AddArgument($Role).AddArgument($RoomState).AddArgument($Lock)
        $handle = $ps.BeginInvoke()

        [void]$Handlers.Add([pscustomobject]@{
            Runspace = $runspace
            PowerShell = $ps
            Handle = $handle
            Socket = $Socket
            Role = $Role
        })
    }
    catch {
        try { $ps.Dispose() } catch { }
        try { $runspace.Close() } catch { }
        try { $runspace.Dispose() } catch { }
        throw
    }
}

function Cleanup-Handlers {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers
    )

    foreach ($entry in @($Handlers.ToArray())) {
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
            try { $entry.PowerShell.Dispose() } catch { }
            try { $entry.Runspace.Close() } catch { }
            try { $entry.Runspace.Dispose() } catch { }
            [void]$Handlers.Remove($entry)
        }
    }
}

function Stop-Handlers {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers
    )

    foreach ($entry in @($Handlers.ToArray())) {
        try {
            if (-not $entry.Handle.IsCompleted) {
                $entry.PowerShell.Stop()
            }
        }
        catch {
        }

        try {
            $null = $entry.PowerShell.EndInvoke($entry.Handle)
        }
        catch {
            if ($_.Exception.Message -notlike "*The pipeline has been stopped*") {
                Write-Host ("Client handler stop failed: {0}" -f $_.Exception.Message)
            }
        }
        finally {
            try { $entry.PowerShell.Dispose() } catch { }
            try { $entry.Runspace.Close() } catch { }
            try { $entry.Runspace.Dispose() } catch { }
        }
    }
}

function Invoke-WebSocketRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers,

        [Parameter(Mandatory = $true)]
        [string]$WorkerModulePath
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -ne "GET" -or ($path -ne "/ws" -and $path -ne "/ws/")) {
        return $false
    }

    if (-not $request.IsWebSocketRequest) {
        Send-TextResponse -Response $response -Text "WebSocket required" -StatusCode 400
        return $true
    }

    try {
        $wsContext = $Context.AcceptWebSocketAsync([System.Management.Automation.Language.NullString]::Value).Result
        $ws = $wsContext.WebSocket

        $role = $null
        $rejectReason = ""
        [System.Threading.Monitor]::Enter($Lock)
        try {
            Sanitize-ClosedSlots -RoomState $RoomState
            $role = Get-AvailableRole -RoomState $RoomState

            if ($null -eq $role) {
                $rejectReason = "room_full"
            }
            else {
                $RoomState.players[$role] = [ordered]@{
                    role = $role
                    socket = $ws
                    input = [hashtable]::Synchronized(@{
                        left = $false
                        right = $false
                        jump = $false
                    })
                }

                $welcomeSent = Send-VolleyMessage -Socket $ws -Payload ([ordered]@{
                    type = "welcome"
                    role = $role
                    world = $RoomState.world
                })

                if (-not $welcomeSent) {
                    $RoomState.players[$role] = $null
                    $rejectReason = "welcome_failed"
                }
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($Lock)
        }

        if ($rejectReason -eq "room_full") {
            [void](Send-VolleyMessage -Socket $ws -Payload ([ordered]@{
                type = "event"
                name = "room_full"
            }))
            Close-VolleySocket -Socket $ws
            return $true
        }

        if ($rejectReason -eq "welcome_failed") {
            Close-VolleySocket -Socket $ws
            return $true
        }

        Write-Host ("Client connected: {0}" -f $role)

        try {
            Start-ClientHandler -Socket $ws -Role $role -RoomState $RoomState -Lock $Lock -Handlers $Handlers -WorkerModulePath $WorkerModulePath
        }
        catch {
            [System.Threading.Monitor]::Enter($Lock)
            try {
                Remove-PlayerBySocket -RoomState $RoomState -Socket $ws
            }
            finally {
                [System.Threading.Monitor]::Exit($Lock)
            }

            Close-VolleySocket -Socket $ws
            Write-Host ("Client handler start failed: {0}" -f $_.Exception.Message)
        }
    }
    catch {
        Write-Host ("WebSocket connection failed: {0}" -f $_.Exception.Message)
    }

    return $true
}

function Invoke-Request {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoomState,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers,

        [Parameter(Mandatory = $true)]
        [string]$WorkerModulePath
    )

    if (Invoke-StaticResourceRoute -Context $Context -AppRoot $AppRoot) {
        return
    }

    if (Invoke-WebSocketRoute -Context $Context -RoomState $RoomState -Lock $Lock -Handlers $Handlers -WorkerModulePath $WorkerModulePath) {
        return
    }

    Send-TextResponse -Response $Context.Response -Text "Not Found" -StatusCode 404
}

function Start-VolleyballServer {
    $appRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $workerModulePath = Join-Path $appRoot "volleyball-worker.psm1"
    Import-Module $workerModulePath -Force

    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://+:8090/"
    $listener.Prefixes.Add($prefix)

    $roomState = Initialize-RoomState
    $lock = New-Object Object
    $handlers = New-Object System.Collections.ArrayList
    $tickIntervalMs = 33
    $nextTick = [DateTime]::UtcNow
    $pendingContext = $null

    Write-Host ("Volleyball server listening on {0}" -f $prefix)
    Write-Host ("Open http://localhost:8090/")

    try {
        $listener.Start()
        $pendingContext = $listener.BeginGetContext($null, $null)

        while ($listener.IsListening) {
            Cleanup-Handlers -Handlers $handlers

            if ($null -ne $pendingContext -and $pendingContext.AsyncWaitHandle.WaitOne(1)) {
                $context = $null
                try {
                    $context = $listener.EndGetContext($pendingContext)
                }
                catch {
                    if (-not $listener.IsListening) { break }
                    Write-Host ("Accept failed: {0}" -f $_.Exception.Message)
                }
                finally {
                    if ($listener.IsListening) {
                        $pendingContext = $listener.BeginGetContext($null, $null)
                    }
                }

                if ($null -ne $context) {
                    try {
                        Invoke-Request -Context $context -AppRoot $appRoot -RoomState $roomState -Lock $lock -Handlers $handlers -WorkerModulePath $workerModulePath
                    }
                    catch {
                        Write-Host ("Request failed: {0}" -f $_.Exception.Message)
                        Send-InternalServerError -Response $context.Response
                    }
                }
            }

            $now = [DateTime]::UtcNow
            if ($now -ge $nextTick) {
                Invoke-GameTick -RoomState $roomState -Lock $lock

                do {
                    $nextTick = $nextTick.AddMilliseconds($tickIntervalMs)
                } while ($nextTick -le $now)
            }
        }
    }
    finally {
        Stop-Handlers -Handlers $handlers

        [System.Threading.Monitor]::Enter($lock)
        try {
            foreach ($role in @("left", "right")) {
                $slot = $roomState.players[$role]
                if ($null -eq $slot) { continue }
                Close-VolleySocket -Socket $slot.socket
                $roomState.players[$role] = $null
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }

        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }
}

Start-VolleyballServer
