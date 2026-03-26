Add-Type -AssemblyName System.Net.Http

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:4608/")
$listener.Start()

Write-Host "Cave server running at http://localhost:4608/"
Write-Host "Open / in a browser. WebSocket endpoint is /ws"

$appRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($appRoot)) {
    $appRoot = (Get-Location).Path
}

$workerModulePath = Join-Path $appRoot "worker.psm1"
$clients = New-Object System.Collections.ArrayList
$lock = New-Object Object
$handlers = New-Object System.Collections.ArrayList

function Send-FileResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$ContentType
    )

    $path = Join-Path $appRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        Send-TextResponse -Response $Response -StatusCode 404 -Text "Not Found"
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $Response.StatusCode = 200
    $Response.ContentType = $ContentType
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-TextResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "text/plain; charset=utf-8"
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-JsonToSocket {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        $Payload
    )

    try {
        if ($Socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            return
        }

        $message = $Payload | ConvertTo-Json -Compress -Depth 8
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)
        $Socket.SendAsync(
            $segment,
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()
    }
    catch {
    }
}

function Send-BroadcastText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

    [System.Threading.Monitor]::Enter($lock)
    try {
        foreach ($entry in @($clients.ToArray())) {
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
        [System.Threading.Monitor]::Exit($lock)
    }
}

function Get-ClientRole {
    [System.Threading.Monitor]::Enter($lock)
    try {
        $hasBlack = $false
        $hasWhite = $false

        foreach ($entry in @($clients.ToArray())) {
            $socket = $entry.Socket
            if ($null -eq $socket) {
                continue
            }

            if ($socket.State -ne [System.Net.WebSockets.WebSocketState]::Open -and $socket.State -ne [System.Net.WebSockets.WebSocketState]::CloseReceived) {
                continue
            }

            if ($entry.Role -eq "black") { $hasBlack = $true }
            if ($entry.Role -eq "white") { $hasWhite = $true }
        }

        if (-not $hasBlack -and -not $hasWhite) {
            return (Get-Random -InputObject @("black", "white"))
        }

        if ($hasBlack -and -not $hasWhite) { return "white" }
        if ($hasWhite -and -not $hasBlack) { return "black" }
        return "spectator"
    }
    finally {
        [System.Threading.Monitor]::Exit($lock)
    }
}

function Add-Client {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    [System.Threading.Monitor]::Enter($lock)
    try {
        [void]$clients.Add([pscustomobject]@{
                Socket = $Socket
                Role = $Role
            })
        return $clients.Count
    }
    finally {
        [System.Threading.Monitor]::Exit($lock)
    }
}

function Remove-ClientBySocket {
    param(
        [Parameter(Mandatory = $true)]
        $Socket
    )

    [System.Threading.Monitor]::Enter($lock)
    try {
        foreach ($entry in @($clients.ToArray())) {
            if ($entry.Socket -ne $Socket) {
                continue
            }

            [void]$clients.Remove($entry)
            break
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($lock)
    }
}

function Close-Socket {
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

function Cleanup-Handlers {
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
            try { $entry.PowerShell.Dispose() }
            catch { }
            try { $entry.Runspace.Close() }
            catch { }
            try { $entry.Runspace.Dispose() }
            catch { }
            [void]$handlers.Remove($entry)
        }
    }
}

function Stop-Handlers {
    foreach ($entry in @($handlers.ToArray())) {
        try {
            if (-not $entry.Handle.IsCompleted) { $entry.PowerShell.Stop() }
        }
        catch {
        }

        try {
            $null = $entry.PowerShell.EndInvoke($entry.Handle)
        }
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

function Start-ClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        $Socket,

        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ImportPSModule(@($workerModulePath))

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($Host, $iss)
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    try {
        $ps.Runspace = $runspace
        $null = $ps.AddCommand("Invoke-CaveClientHandler").AddArgument($Socket).AddArgument($Role).AddArgument($clients).AddArgument($lock)
        $handle = $ps.BeginInvoke()

        [void]$handlers.Add([pscustomobject]@{
                Runspace = $runspace
                PowerShell = $ps
                Handle = $handle
                Socket = $Socket
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
        Cleanup-Handlers

        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            Send-FileResponse -Response $response -FileName "index.html" -ContentType "text/html; charset=utf-8"
            continue
        }

        if ($method -eq "GET" -and $path -eq "/script.js") {
            Send-FileResponse -Response $response -FileName "script.js" -ContentType "application/javascript; charset=utf-8"
            continue
        }

        if ($method -eq "GET" -and $path -eq "/style.css") {
            Send-FileResponse -Response $response -FileName "style.css" -ContentType "text/css; charset=utf-8"
            continue
        }

        if ($path -ne "/ws" -and $path -ne "/ws/") {
            Send-TextResponse -Response $response -StatusCode 404 -Text "Not Found"
            continue
        }

        if (-not $request.IsWebSocketRequest) {
            Send-TextResponse -Response $response -StatusCode 400 -Text "WebSocket required"
            continue
        }

        try {
            $wsContext = $context.AcceptWebSocketAsync([System.Management.Automation.Language.NullString]::Value).Result
            $ws = $wsContext.WebSocket
            $role = Get-ClientRole
            $count = Add-Client -Socket $ws -Role $role
            Write-Host ("Client connected: {0} ({1})" -f $count, $role)

            try {
                Start-ClientHandler -Socket $ws -Role $role
                Send-JsonToSocket -Socket $ws -Payload @{
                    type = "welcome"
                    role = $role
                }
                Send-BroadcastText -Message ((@{
                            type = "peer"
                            event = "join"
                            role = $role
                        } | ConvertTo-Json -Compress))
            }
            catch {
                Write-Host ("Client handler start failed: {0}" -f $_.Exception.Message)
                Remove-ClientBySocket -Socket $ws
                Close-Socket -Socket $ws
            }
        }
        catch {
            Write-Host ("Connection error: {0}" -f $_.Exception.Message)
        }
    }
}
finally {
    Stop-Handlers

    foreach ($entry in @($clients.ToArray())) {
        Close-Socket -Socket $entry.Socket
    }

    if ($listener.IsListening) {
        $listener.Stop()
    }

    $listener.Close()
}
