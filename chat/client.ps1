[CmdletBinding()]
param(
    [string]$ServerUrl = "http://localhost:9999",
    [int]$PollTimeoutSec = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Post-Json {
    param(
        [string]$BaseUrl,
        [string]$Path,
        [hashtable]$Body
    )

    $uri = "{0}{1}" -f $BaseUrl, $Path
    $json = ConvertTo-Json -InputObject $Body -Compress -Depth 4
    Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body $json -TimeoutSec 15
}

$baseUrl = $ServerUrl.TrimEnd("/")

$name = ""
while ([string]::IsNullOrWhiteSpace($name)) {
    $candidate = Read-Host "name(1-20)"
    if ($null -eq $candidate) {
        continue
    }

    $candidate = $candidate.Trim()
    if ($candidate.Length -ge 1 -and $candidate.Length -le 20) {
        $name = $candidate
    }
    else {
        [Console]::WriteLine("name must be 1~20")
    }
}

$join = Post-Json -BaseUrl $baseUrl -Path "/join" -Body @{ name = $name }
$clientId = [string]$join.clientId
if ([string]::IsNullOrWhiteSpace($clientId)) {
    throw "join failed"
}

[Console]::WriteLine(("joined: {0}" -f $name))
[Console]::WriteLine("type message. /exit to quit.")

$shared = [hashtable]::Synchronized(@{
    Stop           = $false
    ServerUrl      = $baseUrl
    ClientId       = $clientId
    Cursor         = [int64]0
    PollTimeoutSec = $PollTimeoutSec
})

$pollScript = {
    param([hashtable]$State)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    while (-not $State.Stop) {
        try {
            $uri = "{0}/poll?clientId={1}&cursor={2}&timeoutSec={3}" -f `
                $State.ServerUrl, `
                [System.Uri]::EscapeDataString($State.ClientId), `
                $State.Cursor, `
                $State.PollTimeoutSec

            $resp = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec ($State.PollTimeoutSec + 10)
            if ($null -eq $resp) {
                continue
            }

            $messages = @()
            if ($null -ne $resp.PSObject.Properties["messages"]) {
                $messages = @($resp.messages)
            }

            foreach ($msg in $messages) {
                $clock = ""
                try {
                    $clock = ([DateTime]::Parse([string]$msg.sentAt)).ToLocalTime().ToString("HH:mm:ss")
                }
                catch {
                    $clock = (Get-Date).ToString("HH:mm:ss")
                }

                [Console]::WriteLine(("[{0}] {1}: {2}" -f $clock, [string]$msg.senderName, [string]$msg.text))

                $id = [int64]$msg.id
                if ($id -gt [int64]$State.Cursor) {
                    $State.Cursor = $id
                }
            }

            if ($null -ne $resp.PSObject.Properties["nextCursor"]) {
                $next = [int64]$resp.nextCursor
                if ($next -gt [int64]$State.Cursor) {
                    $State.Cursor = $next
                }
            }
        }
        catch {
            [Console]::WriteLine(("poll error: {0}" -f $_.Exception.Message))
            Start-Sleep -Seconds 2
        }
    }
}

$poller = [powershell]::Create()
$null = $poller.AddScript($pollScript).AddArgument($shared)
$pollHandle = $poller.BeginInvoke()

try {
    while ($true) {
        $line = Read-Host
        if ($null -eq $line) {
            continue
        }

        if ($line -eq "/exit") {
            break
        }

        $text = $line.Trim()
        if ($text.Length -eq 0) {
            continue
        }
        if ($text.Length -gt 500) {
            [Console]::WriteLine("max 500 chars")
            continue
        }

        try {
            $null = Post-Json -BaseUrl $baseUrl -Path "/send" -Body @{
                clientId = $clientId
                text     = $text
            }
        }
        catch {
            [Console]::WriteLine(("send error: {0}" -f $_.Exception.Message))
        }
    }
}
finally {
    $shared.Stop = $true

    try {
        $null = Post-Json -BaseUrl $baseUrl -Path "/leave" -Body @{ clientId = $clientId }
    }
    catch {
    }

    try {
        $pollHandle.AsyncWaitHandle.WaitOne(30000) | Out-Null
    }
    catch {
    }

    try {
        $poller.EndInvoke($pollHandle)
    }
    catch {
    }
    finally {
        $poller.Dispose()
    }
}
