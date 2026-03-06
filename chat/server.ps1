[CmdletBinding()]
param(
    [int]$Port = 9999,
    [string]$BindAddress = "localhost",
    [int]$DefaultPollTimeoutSec = 20,
    [int]$MaxPollTimeoutSec = 30,
    [int]$MaxMessages = 200,
    [int]$IdleCleanupMinutes = 10,
    [int]$MaxWorkers = 16
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-IsoNow {
    [DateTime]::UtcNow.ToString("o")
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

function Cleanup-IdleClients {
    param(
        [hashtable]$State,
        [int]$IdleMinutes
    )

    $threshold = [DateTime]::UtcNow.AddMinutes(-1 * $IdleMinutes)

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        foreach ($clientId in @($State.Clients.Keys)) {
            $client = $State.Clients[$clientId]
            if ($null -eq $client) {
                continue
            }

            if ([DateTime]$client.lastSeenAt -lt $threshold) {
                $State.Clients.Remove($clientId) | Out-Null
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

$state = [hashtable]::Synchronized(@{
    Lock    = New-Object object
    Clients = [hashtable]::Synchronized(@{})
    Messages = New-Object System.Collections.ArrayList
    NextId  = [int64]0
    Running = $true
})

$settings = [hashtable]::Synchronized(@{
    DefaultPollTimeoutSec = $DefaultPollTimeoutSec
    MaxPollTimeoutSec     = $MaxPollTimeoutSec
    MaxMessages           = $MaxMessages
})

$handlerScript = {
    param(
        [System.Net.HttpListenerContext]$Context,
        [hashtable]$State,
        [hashtable]$Settings
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    function Get-IsoNow {
        [DateTime]::UtcNow.ToString("o")
    }

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

    function Send-Json {
        param(
            [System.Net.HttpListenerContext]$Ctx,
            [int]$StatusCode,
            [object]$Body
        )

        $response = $Ctx.Response
        $response.StatusCode = $StatusCode
        $response.ContentType = "application/json; charset=utf-8"
        $response.ContentEncoding = [System.Text.Encoding]::UTF8
        Add-Cors -Response $response

        if ($null -eq $Body) {
            $response.ContentLength64 = 0
            Close-Response -Response $response
            return
        }

        $json = ConvertTo-Json -InputObject $Body -Depth 6 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        Close-Response -Response $response
    }

    function Send-Error {
        param(
            [System.Net.HttpListenerContext]$Ctx,
            [int]$StatusCode,
            [string]$Code,
            [string]$Message
        )

        Send-Json -Ctx $Ctx -StatusCode $StatusCode -Body ([ordered]@{
                error      = [ordered]@{
                    code    = $Code
                    message = $Message
                }
                serverTime = Get-IsoNow
            })
    }

    function Read-JsonBody {
        param([System.Net.HttpListenerRequest]$Request)

        if (-not $Request.HasEntityBody) {
            return $null
        }

        $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
        try {
            $raw = $reader.ReadToEnd()
        }
        finally {
            $reader.Close()
        }

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        try {
            ConvertFrom-Json -InputObject $raw
        }
        catch {
            throw "invalid JSON body"
        }
    }

    function Get-Value {
        param(
            [object]$InputObject,
            [string]$Name
        )

        if ($null -eq $InputObject) {
            return $null
        }

        $prop = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $prop) {
            return $null
        }

        $prop.Value
    }

    function Parse-Int64 {
        param(
            [string]$Value,
            [int64]$DefaultValue
        )

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $DefaultValue
        }

        $parsed = [int64]0
        if ([int64]::TryParse($Value, [ref]$parsed)) {
            return $parsed
        }

        $DefaultValue
    }

    function Parse-Int {
        param(
            [string]$Value,
            [int]$DefaultValue
        )

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $DefaultValue
        }

        $parsed = 0
        if ([int]::TryParse($Value, [ref]$parsed)) {
            return $parsed
        }

        $DefaultValue
    }

    try {
        $request = $Context.Request
        $path = $request.Url.AbsolutePath.ToLowerInvariant()
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($method -eq "OPTIONS") {
            Send-Json -Ctx $Context -StatusCode 204 -Body $null
            return
        }

        switch ($path) {
            "/join" {
                if ($method -ne "POST") {
                    Send-Error -Ctx $Context -StatusCode 405 -Code "method_not_allowed" -Message "Use POST."
                    return
                }

                $payload = Read-JsonBody -Request $request
                $name = [string](Get-Value -InputObject $payload -Name "name")
                $name = $name.Trim()

                if ($name.Length -lt 1 -or $name.Length -gt 20) {
                    Send-Error -Ctx $Context -StatusCode 400 -Code "invalid_name" -Message "name must be 1 to 20 characters."
                    return
                }

                $clientId = [guid]::NewGuid().ToString()
                $joinedAt = Get-IsoNow

                [System.Threading.Monitor]::Enter($State.Lock)
                try {
                    $State.Clients[$clientId] = [ordered]@{
                        name       = $name
                        joinedAt   = $joinedAt
                        lastSeenAt = [DateTime]::UtcNow
                    }
                }
                finally {
                    [System.Threading.Monitor]::Exit($State.Lock)
                }

                Send-Json -Ctx $Context -StatusCode 200 -Body ([ordered]@{
                        clientId = $clientId
                        name     = $name
                        joinedAt = $joinedAt
                    })
                return
            }

            "/send" {
                if ($method -ne "POST") {
                    Send-Error -Ctx $Context -StatusCode 405 -Code "method_not_allowed" -Message "Use POST."
                    return
                }

                $payload = Read-JsonBody -Request $request
                $clientId = [string](Get-Value -InputObject $payload -Name "clientId")
                $text = [string](Get-Value -InputObject $payload -Name "text")

                if ([string]::IsNullOrWhiteSpace($clientId)) {
                    Send-Error -Ctx $Context -StatusCode 400 -Code "invalid_client_id" -Message "clientId is required."
                    return
                }

                if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 500) {
                    Send-Error -Ctx $Context -StatusCode 400 -Code "invalid_text" -Message "text must be 1 to 500 characters."
                    return
                }

                $messageId = [int64]0
                [System.Threading.Monitor]::Enter($State.Lock)
                try {
                    if (-not $State.Clients.ContainsKey($clientId)) {
                        Send-Error -Ctx $Context -StatusCode 401 -Code "unauthorized_client" -Message "clientId is not active."
                        return
                    }

                    $senderName = [string]$State.Clients[$clientId].name
                    $State.Clients[$clientId].lastSeenAt = [DateTime]::UtcNow

                    $State.NextId = [int64]$State.NextId + 1
                    $messageId = [int64]$State.NextId

                    $message = [ordered]@{
                        id         = $messageId
                        senderName = $senderName
                        text       = $text
                        sentAt     = Get-IsoNow
                    }

                    [void]$State.Messages.Add($message)
                    while ($State.Messages.Count -gt $Settings.MaxMessages) {
                        $State.Messages.RemoveAt(0)
                    }
                }
                finally {
                    [System.Threading.Monitor]::Exit($State.Lock)
                }

                Send-Json -Ctx $Context -StatusCode 202 -Body ([ordered]@{
                        accepted   = $true
                        messageId  = $messageId
                        serverTime = Get-IsoNow
                    })
                return
            }

            "/poll" {
                if ($method -ne "GET") {
                    Send-Error -Ctx $Context -StatusCode 405 -Code "method_not_allowed" -Message "Use GET."
                    return
                }

                $clientId = [string]$request.QueryString["clientId"]
                if ([string]::IsNullOrWhiteSpace($clientId)) {
                    Send-Error -Ctx $Context -StatusCode 400 -Code "invalid_client_id" -Message "clientId is required."
                    return
                }

                $cursor = Parse-Int64 -Value ([string]$request.QueryString["cursor"]) -DefaultValue ([int64]0)
                $timeoutSec = Parse-Int -Value ([string]$request.QueryString["timeoutSec"]) -DefaultValue $Settings.DefaultPollTimeoutSec
                if ($timeoutSec -lt 1) {
                    $timeoutSec = 1
                }
                if ($timeoutSec -gt $Settings.MaxPollTimeoutSec) {
                    $timeoutSec = $Settings.MaxPollTimeoutSec
                }

                $startedAt = [DateTime]::UtcNow
                $result = @()

                while ($true) {
                    [System.Threading.Monitor]::Enter($State.Lock)
                    try {
                        if (-not $State.Clients.ContainsKey($clientId)) {
                            Send-Error -Ctx $Context -StatusCode 401 -Code "unauthorized_client" -Message "clientId is not active."
                            return
                        }

                        $State.Clients[$clientId].lastSeenAt = [DateTime]::UtcNow

                        $result = @()
                        foreach ($item in $State.Messages) {
                            if ([int64]$item.id -gt $cursor) {
                                $result += $item
                            }
                        }
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($State.Lock)
                    }

                    if ($result.Count -gt 0) {
                        break
                    }

                    if (([DateTime]::UtcNow - $startedAt).TotalSeconds -ge $timeoutSec) {
                        break
                    }

                    Start-Sleep -Milliseconds 300
                }

                $nextCursor = $cursor
                foreach ($item in $result) {
                    $itemId = [int64]$item.id
                    if ($itemId -gt $nextCursor) {
                        $nextCursor = $itemId
                    }
                }

                Send-Json -Ctx $Context -StatusCode 200 -Body ([ordered]@{
                        messages   = $result
                        nextCursor = $nextCursor
                        serverTime = Get-IsoNow
                    })
                return
            }

            "/leave" {
                if ($method -ne "POST") {
                    Send-Error -Ctx $Context -StatusCode 405 -Code "method_not_allowed" -Message "Use POST."
                    return
                }

                $payload = Read-JsonBody -Request $request
                $clientId = [string](Get-Value -InputObject $payload -Name "clientId")
                if ([string]::IsNullOrWhiteSpace($clientId)) {
                    Send-Error -Ctx $Context -StatusCode 400 -Code "invalid_client_id" -Message "clientId is required."
                    return
                }

                $removed = $false
                [System.Threading.Monitor]::Enter($State.Lock)
                try {
                    if ($State.Clients.ContainsKey($clientId)) {
                        $State.Clients.Remove($clientId) | Out-Null
                        $removed = $true
                    }
                }
                finally {
                    [System.Threading.Monitor]::Exit($State.Lock)
                }

                Send-Json -Ctx $Context -StatusCode 200 -Body ([ordered]@{
                        left = $removed
                    })
                return
            }

            "/health" {
                if ($method -ne "GET") {
                    Send-Error -Ctx $Context -StatusCode 405 -Code "method_not_allowed" -Message "Use GET."
                    return
                }

                Send-Json -Ctx $Context -StatusCode 200 -Body ([ordered]@{
                        status     = "ok"
                        serverTime = Get-IsoNow
                    })
                return
            }

            default {
                Send-Error -Ctx $Context -StatusCode 404 -Code "not_found" -Message "endpoint not found."
                return
            }
        }
    }
    catch {
        try {
            Send-Error -Ctx $Context -StatusCode 500 -Code "internal_error" -Message $_.Exception.Message
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

    [Console]::WriteLine(("chat server listening on http://{0}:{1}" -f $BindAddress, $Port))
    [Console]::WriteLine("for LAN, use your host IP as -BindAddress and connect clients to that IP")

    $nextCleanupAt = [DateTime]::UtcNow.AddSeconds(30)
    while ($listener.IsListening) {
        $pending = $listener.BeginGetContext($null, $null)

        while (-not $pending.AsyncWaitHandle.WaitOne(1000)) {
            if ([DateTime]::UtcNow -ge $nextCleanupAt) {
                Cleanup-IdleClients -State $state -IdleMinutes $IdleCleanupMinutes
                Cleanup-CompletedRequests -ActiveRequests $activeRequests
                $nextCleanupAt = [DateTime]::UtcNow.AddSeconds(30)
            }
        }

        $context = $listener.EndGetContext($pending)
        Cleanup-CompletedRequests -ActiveRequests $activeRequests

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
