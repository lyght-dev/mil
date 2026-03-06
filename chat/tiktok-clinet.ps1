[CmdletBinding()]
param(
    [string]$ServerUrl = "http://localhost:9998/tiktok"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    $response = Invoke-WebRequest -Method Post -Uri $ServerUrl -Body "tick" -ContentType "text/plain" -TimeoutSec 10
    [Console]::WriteLine($response.Content)
}
catch {
    [Console]::Error.WriteLine(("request failed: {0}" -f $_.Exception.Message))
    exit 1
}
