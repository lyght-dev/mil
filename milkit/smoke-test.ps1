$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'milkit.psm1'
Import-Module $modulePath -Force

$port = Get-Random -Minimum 18000 -Maximum 24000
$hostName = '127.0.0.1'
$baseUrl = "http://$hostName`:$port"
$publicRoot = Join-Path $PSScriptRoot 'smoke-public'
New-Item -ItemType Directory -Path $publicRoot -Force | Out-Null
Set-Content -Path (Join-Path $publicRoot 'index.html') -Value 'SMOKE_STATIC' -Encoding utf8

$job = Start-Job -ScriptBlock {
    param($modulePath, $rootPath, $port)

    Import-Module $modulePath -Force
    $script:app = New-App -Root $rootPath -Name 'smoke'

    Use $script:app {
        param($req, $res, $next)
        if ($req.Path -eq '/mw-return') {
            return @{
                source = 'middleware'
                ok = $true
            }
        }

        return & $next
    }

    Add-Route $script:app GET '/text' {
        param($req, $res)
        return 'hello'
    }

    Add-Route $script:app GET '/json-object' {
        param($req, $res)
        return @{ value = 1 }
    }

    Add-Route $script:app GET '/json-array' {
        param($req, $res)
        return @('a', 'b')
    }

    Add-Route $script:app GET '/explicit' {
        param($req, $res)
        $res.Ok(@{ explicit = $true })
    }

    Add-Route $script:app GET '/boom' {
        param($req, $res)
        throw 'boom'
    }

    Add-Route $script:app GET '/__stop' {
        param($req, $res)
        $res.Text('stopping')
        Stop-App -App $script:app
    }

    Use-Static $script:app '/public' './smoke-public'

    Set-NotFoundHandler $script:app {
        param($req, $res)
        return @{ kind = 'notfound' }
    }

    Set-ErrorHandler $script:app {
        param($req, $res, $err)
        return @{ kind = 'error'; message = $err.Exception.Message }
    }

    Start-App -App $script:app -BindHost '127.0.0.1' -Port $port
} -ArgumentList $modulePath, $PSScriptRoot, $port

function Assert-Eq {
    param(
        [string]$Name,
        $Actual,
        $Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected [$Expected] but got [$Actual]"
    }
}

function Get-Json {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    return $response.Content | ConvertFrom-Json
}

function Wait-ServerReady {
    param(
        [string]$ProbeUrl,
        [System.Management.Automation.Job]$Job,
        [int]$TimeoutSeconds = 10
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Job.State -in @('Failed', 'Stopped', 'Completed')) {
            $reason = $Job.ChildJobs[0].JobStateInfo.Reason
            if ($null -ne $reason) {
                throw "Server job ended before ready: $($reason.Message)"
            }

            throw "Server job ended before ready. state=$($Job.State)"
        }

        try {
            Invoke-WebRequest -Uri $ProbeUrl -UseBasicParsing -TimeoutSec 2 | Out-Null
            return
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    throw "Server did not become ready within $TimeoutSeconds seconds."
}

try {
    Wait-ServerReady -ProbeUrl "$baseUrl/text" -Job $job

    Assert-Eq -Name 'text response' -Actual (Invoke-WebRequest -Uri "$baseUrl/text" -UseBasicParsing).Content -Expected 'hello'
    Assert-Eq -Name 'object json' -Actual (Get-Json -Url "$baseUrl/json-object").value -Expected 1
    Assert-Eq -Name 'array json length' -Actual ((Get-Json -Url "$baseUrl/json-array").Count) -Expected 2
    Assert-Eq -Name 'middleware return' -Actual (Get-Json -Url "$baseUrl/mw-return").source -Expected 'middleware'
    Assert-Eq -Name 'explicit ok' -Actual (Get-Json -Url "$baseUrl/explicit").explicit -Expected $true
    Assert-Eq -Name 'static index' -Actual (Invoke-WebRequest -Uri "$baseUrl/public" -UseBasicParsing).Content.Trim() -Expected 'SMOKE_STATIC'
    Assert-Eq -Name 'not found handler' -Actual (Get-Json -Url "$baseUrl/missing").kind -Expected 'notfound'
    Assert-Eq -Name 'error handler' -Actual (Get-Json -Url "$baseUrl/boom").kind -Expected 'error'

    Invoke-WebRequest -Uri "$baseUrl/__stop" -UseBasicParsing | Out-Null
    Wait-Job -Job $job -Timeout 5 | Out-Null

    if ($job.State -ne 'Completed') {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        throw "Server job did not stop. state=$($job.State)"
    }

    $jobErrors = @($job.ChildJobs[0].Error)
    if ($jobErrors.Count -gt 0) {
        throw "Server job had errors: $($jobErrors[0])"
    }

    'OK'
}
finally {
    if ($null -ne $job) {
        if ($job.State -in @('Running', 'NotStarted')) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
        }

        Remove-Job -Job $job -ErrorAction SilentlyContinue
    }
}
