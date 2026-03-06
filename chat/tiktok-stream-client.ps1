[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:9997",
    [switch]$SendTick,
    [int]$WaitTimeoutSec = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Send-Tick {
    param([string]$ServerBaseUrl)

    $response = Invoke-WebRequest -Method Post -Uri ("{0}/tick" -f $ServerBaseUrl.TrimEnd("/")) -Body "tick" -ContentType "text/plain" -TimeoutSec 10
    [Console]::WriteLine(("tick response: {0}" -f $response.Content))
}

$shared = [hashtable]::Synchronized(@{
    Sent = $false
})

$base = $BaseUrl.TrimEnd("/")
$request = [System.Net.HttpWebRequest]::Create(("{0}/stream" -f $base))
$request.Method = "GET"
$request.Accept = "text/event-stream"
$request.Timeout = -1
$request.ReadWriteTimeout = -1

$response = $null
$reader = $null

try {
    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)

    [Console]::WriteLine(("connected: {0}/stream" -f $base))

    if ($SendTick) {
        Start-Sleep -Milliseconds 300
        Send-Tick -ServerBaseUrl $base
        $shared.Sent = $true
    }

    $startedAt = [DateTime]::UtcNow
    $eventName = ""
    $data = ""

    while ($true) {
        if ($WaitTimeoutSec -gt 0 -and ([DateTime]::UtcNow - $startedAt).TotalSeconds -ge $WaitTimeoutSec) {
            [Console]::WriteLine("timeout")
            break
        }

        $line = $reader.ReadLine()
        if ($null -eq $line) {
            [Console]::WriteLine("stream closed")
            break
        }

        if ($line.StartsWith(":")) {
            continue
        }

        if ($line.StartsWith("event:")) {
            $eventName = $line.Substring(6).Trim()
            continue
        }

        if ($line.StartsWith("data:")) {
            $data = $line.Substring(5).Trim()
            continue
        }

        if ($line.Length -eq 0) {
            if ($eventName.Length -gt 0 -or $data.Length -gt 0) {
                [Console]::WriteLine(("event={0} data={1}" -f $eventName, $data))
                break
            }
        }
    }
}
catch {
    [Console]::Error.WriteLine(("request failed: {0}" -f $_.Exception.Message))
    exit 1
}
finally {
    if ($null -ne $reader) {
        $reader.Close()
    }

    if ($null -ne $response) {
        $response.Close()
    }
}
