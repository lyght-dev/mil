Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PingResult {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.NetworkInformation.Ping]$Ping,

        [Parameter(Mandatory = $true)]
        [string]$HostAddress
    )

    try {
        $reply = $Ping.Send($HostAddress, 5000)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { return @{
            Status = "success"
            Rtt = [int64]$reply.RoundtripTime
            SucceededAt = [DateTime]::UtcNow.ToString("o")
        } }

        return @{
            Status = "timeout"
            Rtt = $null
            SucceededAt = $null
        }
    } catch {
        return @{
            Status = "error"
            Rtt = $null
            SucceededAt = $null
        }
    }
}

function Set-PingResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HostEntry,

        [Parameter(Mandatory = $true)]
        [hashtable]$PingResults,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    [System.Threading.Monitor]::Enter($Lock)
    try {
        $key = [string]$HostEntry.Index
        $current = $PingResults[$key]

        if ($null -eq $current) { $current = [ordered]@{
            destination = $HostEntry.Name
            status = $Result.Status
            rtt = $Result.Rtt
            succeededAt = $null
        } }

        $current.destination = $HostEntry.Name
        $current.status = $Result.Status
        $current.rtt = $Result.Rtt

        if ($null -ne $Result.SucceededAt) { $current.succeededAt = $Result.SucceededAt }

        $PingResults[$key] = $current
    } finally {
        [System.Threading.Monitor]::Exit($Lock)
    }
}

function Invoke-PingSweep {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$HostEntries,

        [Parameter(Mandatory = $true)]
        [hashtable]$PingResults,

        [Parameter(Mandatory = $true)]
        [object]$Lock
    )

    $ping = New-Object System.Net.NetworkInformation.Ping

    try {
        foreach ($hostEntry in $HostEntries) {
            $result = Get-PingResult -Ping $ping -HostAddress $hostEntry.Address
            Set-PingResult -HostEntry $hostEntry -PingResults $PingResults -Lock $Lock -Result $result
        }
    } finally { $ping.Dispose() }
}

function Invoke-PingWorkerLoop {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$HostEntries,

        [Parameter(Mandatory = $true)]
        [hashtable]$PingResults,

        [Parameter(Mandatory = $true)]
        [object]$Lock,

        [Parameter(Mandatory = $true)]
        [hashtable]$WorkerState,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalSeconds
    )

    while (-not $WorkerState.Stop) {
        for ($tick = 0; $tick -lt $PollIntervalSeconds; $tick += 1) {
            if ($WorkerState.Stop) { break }

            Start-Sleep -Seconds 1
        }

        if ($WorkerState.Stop) { break }

        Invoke-PingSweep -HostEntries $HostEntries -PingResults $PingResults -Lock $Lock
    }
}

Export-ModuleMember -Function Invoke-PingSweep, Invoke-PingWorkerLoop
