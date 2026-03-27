# ACS Server Setting API Diff Guide

이 문서는 **`setting` 관련 코드가 전혀 없는 기존 `server.ps1`** 기준에서,
현재 동작(설정 CRUD + serial 재발급 + `list.json` 반영)을 만들기 위해
무엇을 추가/교체해야 하는지 정리한 실제 코드 가이드다.

아래 순서대로 반영하면 된다.

## 1) 스크립트 상단 공용 변수 추가

`Set-StrictMode`, `$ErrorActionPreference` 아래에 추가:

```powershell
$script:AppRoot = ""
$script:LogPath = ""
$script:ListPath = ""
$script:AllowedIds = @{}
$script:SerialToMember = @{}
$script:Prefix = "http://+:8888/"
```

## 2) 공용 JSON 파서 함수 추가

`Get-StringField` 아래에 추가:

```powershell
function Read-JsonPayload {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    try {
        return (Get-RequestBodyText -Request $Request | ConvertFrom-Json)
    } catch {
        Send-RejectedResponse -Response $Response -Message "invalid json"
        return $null
    }
}
```

## 3) `setting` 전용 블록 전체 추가

`server.ps1`에 아래 블록을 **그대로 추가**:

```powershell
###### setting begin ######
function Import-Members {
    $items = Get-Content -LiteralPath $script:ListPath -Raw | ConvertFrom-Json
    $members = @($items)
    $allowedIds = @{}
    $serialToMember = @{}

    foreach ($member in $members) {
        $id = Get-StringField -Object $member -Name "id"
        if (-not [string]::IsNullOrWhiteSpace($id)) { $allowedIds[$id] = $true }

        $serial = Get-StringField -Object $member -Name "serial"
        if (-not [string]::IsNullOrWhiteSpace($serial)) { $serialToMember[$serial] = $member }
    }

    return @{
        Members = $members
        AllowedIds = $allowedIds
        SerialToMember = $serialToMember
    }
}

function Save-Members {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Members
    )

    $json = @($Members) | ConvertTo-Json -Depth 8
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($script:ListPath, $json, $encoding)
}

function Sync-MemberCaches {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Members,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$SerialToMember
    )

    $AllowedIds.Clear()
    $SerialToMember.Clear()

    foreach ($member in $Members) {
        $id = Get-StringField -Object $member -Name "id"
        if (-not [string]::IsNullOrWhiteSpace($id)) { $AllowedIds[$id] = $true }

        $serial = Get-StringField -Object $member -Name "serial"
        if (-not [string]::IsNullOrWhiteSpace($serial)) { $SerialToMember[$serial] = $member }
    }
}

function Find-MemberById {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Members,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    foreach ($member in $Members) {
        if ((Get-StringField -Object $member -Name "id") -eq $Id) { return $member }
    }

    return $null
}

function Set-MemberField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Member,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Member.PSObject.Properties[$Name]) {
        $Member.$Name = $Value
        return
    }

    Add-Member -InputObject $Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-KstNowText {
    return ([DateTime]::UtcNow.AddHours(9)).ToString("yyyy-MM-dd HH:mm:ss 'KST'")
}

function New-MemberSerial {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Members,

        [string]$ExcludeId = ""
    )

    $usedSerials = @{}
    foreach ($member in $Members) {
        $id = Get-StringField -Object $member -Name "id"
        if (-not [string]::IsNullOrWhiteSpace($ExcludeId) -and $id -eq $ExcludeId) { continue }

        $serial = Get-StringField -Object $member -Name "serial"
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }
        $usedSerials[$serial] = $true
    }

    while ($true) {
        $candidate = (Get-Random -Minimum 0 -Maximum 1000000).ToString("D6")
        if ($usedSerials.ContainsKey($candidate)) { continue }
        return $candidate
    }
}

function Invoke-SettingApiRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$SerialToMember
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -eq "POST" -and $path -eq "/setting/member/create") {
        $payload = Read-JsonPayload -Request $request -Response $response
        if ($null -eq $payload) { return $true }

        $id = Get-StringField -Object $payload -Name "id"
        $name = Get-StringField -Object $payload -Name "name"
        $unit = Get-StringField -Object $payload -Name "unit"
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($unit)) {
            Send-RejectedResponse -Response $response -Message "id, name, unit are required"
            return $true
        }

        $members = (Import-Members).Members
        if ($null -ne (Find-MemberById -Members $members -Id $id)) {
            Send-RejectedResponse -Response $response -Message "id already exists"
            return $true
        }

        $newMember = [PSCustomObject]@{
            serial = (New-MemberSerial -Members $members)
            serialLastReissuedAtKst = (Get-KstNowText)
            id = $id
            name = $name
            unit = $unit
        }
        $nextMembers = @($members + $newMember)

        try {
            Save-Members -Members $nextMembers
        } catch {
            Send-RejectedResponse -Response $response -Message "failed to write list" -StatusCode 500
            return $true
        }

        Sync-MemberCaches -Members $nextMembers -AllowedIds $AllowedIds -SerialToMember $SerialToMember
        Send-JsonResponse -Response $response -Payload @{ status = "created"; member = $newMember }
        return $true
    }

    if ($method -eq "POST" -and $path -eq "/setting/member/update") {
        $payload = Read-JsonPayload -Request $request -Response $response
        if ($null -eq $payload) { return $true }

        $id = Get-StringField -Object $payload -Name "id"
        $name = Get-StringField -Object $payload -Name "name"
        $unit = Get-StringField -Object $payload -Name "unit"
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($unit)) {
            Send-RejectedResponse -Response $response -Message "id, name, unit are required"
            return $true
        }

        $members = (Import-Members).Members
        $target = Find-MemberById -Members $members -Id $id
        if ($null -eq $target) {
            Send-RejectedResponse -Response $response -Message "id not found" -StatusCode 404
            return $true
        }

        Set-MemberField -Member $target -Name "name" -Value $name
        Set-MemberField -Member $target -Name "unit" -Value $unit

        try {
            Save-Members -Members $members
        } catch {
            Send-RejectedResponse -Response $response -Message "failed to write list" -StatusCode 500
            return $true
        }

        Sync-MemberCaches -Members $members -AllowedIds $AllowedIds -SerialToMember $SerialToMember
        Send-JsonResponse -Response $response -Payload @{ status = "updated"; member = $target }
        return $true
    }

    if ($method -eq "POST" -and $path -eq "/setting/member/delete") {
        $payload = Read-JsonPayload -Request $request -Response $response
        if ($null -eq $payload) { return $true }

        $id = Get-StringField -Object $payload -Name "id"
        if ([string]::IsNullOrWhiteSpace($id)) {
            Send-RejectedResponse -Response $response -Message "id is required"
            return $true
        }

        $members = (Import-Members).Members
        $nextMembers = @()
        $removed = $false

        foreach ($member in $members) {
            if ((Get-StringField -Object $member -Name "id") -eq $id) {
                $removed = $true
                continue
            }

            $nextMembers += $member
        }

        if (-not $removed) {
            Send-RejectedResponse -Response $response -Message "id not found" -StatusCode 404
            return $true
        }

        try {
            Save-Members -Members $nextMembers
        } catch {
            Send-RejectedResponse -Response $response -Message "failed to write list" -StatusCode 500
            return $true
        }

        Sync-MemberCaches -Members $nextMembers -AllowedIds $AllowedIds -SerialToMember $SerialToMember
        Send-JsonResponse -Response $response -Payload @{ status = "deleted"; id = $id }
        return $true
    }

    if ($method -eq "POST" -and $path -eq "/setting/member/reissue") {
        $payload = Read-JsonPayload -Request $request -Response $response
        if ($null -eq $payload) { return $true }

        $id = Get-StringField -Object $payload -Name "id"
        if ([string]::IsNullOrWhiteSpace($id)) {
            Send-RejectedResponse -Response $response -Message "id is required"
            return $true
        }

        $members = (Import-Members).Members
        $target = Find-MemberById -Members $members -Id $id
        if ($null -eq $target) {
            Send-RejectedResponse -Response $response -Message "id not found" -StatusCode 404
            return $true
        }

        Set-MemberField -Member $target -Name "serial" -Value (New-MemberSerial -Members $members -ExcludeId $id)
        Set-MemberField -Member $target -Name "serialLastReissuedAtKst" -Value (Get-KstNowText)

        try {
            Save-Members -Members $members
        } catch {
            Send-RejectedResponse -Response $response -Message "failed to write list" -StatusCode 500
            return $true
        }

        Sync-MemberCaches -Members $members -AllowedIds $AllowedIds -SerialToMember $SerialToMember
        Send-JsonResponse -Response $response -Payload @{ status = "reissued"; member = $target }
        return $true
    }

    return $false
}
###### setting end ######
```

## 4) `Invoke-AccessRoute` JSON 파서 호출 변경

기존:

```powershell
$payload = Read-AccessPayload -Request $Request -Response $Response
```

변경:

```powershell
$payload = Read-JsonPayload -Request $Request -Response $Response
```

## 5) `Invoke-ApiRoute`에 setting 라우트 위임 추가

`/access` 분기 전에 아래 한 줄 추가:

```powershell
if (Invoke-SettingApiRoute -Context $Context -AllowedIds $AllowedIds -SerialToMember $SerialToMember) { return $true }
```

## 6) `Start-AcsServer` 초기화 교체

`Start-AcsServer`는 아래 방식으로 초기화:

```powershell
function Start-AcsServer {
    $script:AppRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $script:LogPath = Join-Path $script:AppRoot "logs/access-log.csv"
    $script:ListPath = Join-Path $script:AppRoot "list.json"
    $membersData = Import-Members
    $script:AllowedIds = $membersData.AllowedIds
    $script:SerialToMember = $membersData.SerialToMember

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($script:Prefix)

    Write-Host ("ACS listening on {0}" -f $script:Prefix)
    Write-Host ("App root: {0}" -f $script:AppRoot)
    Write-Host ("Log path: {0}" -f $script:LogPath)
    Write-Host ("List path: {0}" -f $script:ListPath)

    try {
        $listener.Start()

        while ($listener.IsListening) {
            $context = $listener.GetContext()

            try {
                Invoke-Request -Context $context -AppRoot $script:AppRoot -LogPath $script:LogPath -AllowedIds $script:AllowedIds -SerialToMember $script:SerialToMember
            } catch {
                Send-InternalServerError -Response $context.Response
            }
        }
    } finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}
```

## 7) 검증 커맨드

```bash
pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"
```

```bash
node --check /workspaces/mil/acs/setting.js
```

## 8) 주의

- 이 문서는 `server.ps1` 기준 diff 가이드다.
- `setting.js`는 이미 `/setting/member/*`를 호출하도록 되어 있어야 한다.
- `list.json`은 `serial`, `id`, `name`, `unit`을 유지해야 하며, 재발급 시 `serialLastReissuedAtKst`가 갱신된다.
