Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'milkit/milkit.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'milkit-utils.psm1') -Force

$script:AppRoot = ''
$script:LogPath = ''
$script:ListPath = ''
$script:AllowedIds = @{}
$script:SerialToMember = @{}
$script:SseClients = [System.Collections.ArrayList]::new()
$script:SseClientsLock = New-Object object
$script:Prefix = 'http://+:8888/'

function Send-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$ContentType
    )

    $filePath = Join-Path $script:AppRoot $RelativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $null = $Response.Status(500)
        $null = $Response.Text('Missing file')
        return
    }

    $text = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)
    $null = $Response.Text($text, $ContentType)
}

function Get-StringField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return ''
    }

    return [string]$property.Value
}

function Send-RejectedResponse {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$StatusCode = 400
    )

    $null = $Response.Status($StatusCode)
    $null = $Response.Json(@{
        status = 'rejected'
        message = $Message
    })
}

function Read-JsonPayload {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [Parameter(Mandatory = $true)]
        [psobject]$Response
    )

    try {
        $payload = $Request.Json()
    }
    catch {
        Send-RejectedResponse -Response $Response -Message 'invalid json'
        return $null
    }

    if ($null -eq $payload) {
        Send-RejectedResponse -Response $Response -Message 'request body is required'
        return $null
    }

    return $payload
}

function Import-Members {
    $items = Get-Content -LiteralPath $script:ListPath -Raw | ConvertFrom-Json
    $members = @($items)
    $allowedIds = @{}
    $serialToMember = @{}

    foreach ($member in $members) {
        $id = Get-StringField -Object $member -Name 'id'
        if (-not (Test-Blank $id)) {
            $allowedIds[$id] = $true
        }

        $serial = Get-StringField -Object $member -Name 'serial'
        if (-not (Test-Blank $serial)) {
            $serialToMember[$serial] = $member
        }
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
        $id = Get-StringField -Object $member -Name 'id'
        if (-not (Test-Blank $id)) {
            $AllowedIds[$id] = $true
        }

        $serial = Get-StringField -Object $member -Name 'serial'
        if (-not (Test-Blank $serial)) {
            $SerialToMember[$serial] = $member
        }
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
        if ((Get-StringField -Object $member -Name 'id') -eq $Id) {
            return $member
        }
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

        [string]$ExcludeId = ''
    )

    $usedSerials = @{}
    foreach ($member in $Members) {
        $id = Get-StringField -Object $member -Name 'id'
        if (-not (Test-Blank $ExcludeId) -and $id -eq $ExcludeId) {
            continue
        }

        $serial = Get-StringField -Object $member -Name 'serial'
        if (Test-Blank $serial) {
            continue
        }

        $usedSerials[$serial] = $true
    }

    while ($true) {
        $candidate = (Get-Random -Minimum 0 -Maximum 1000000).ToString('D6')
        if ($usedSerials.ContainsKey($candidate)) {
            continue
        }

        return $candidate
    }
}

function New-AccessLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding
    )

    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Blank $dir) -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir)
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        [System.IO.File]::WriteAllText($LogPath, "time,type,location,id`n", $Encoding)
    }
}

function New-AccessRecordLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    return ('{0},{1},{2},{3}' -f [DateTime]::UtcNow.ToString('o'), $Type, $Location, $Id)
}

function Add-AccessRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $line = New-AccessRecordLine -Type $Type -Location $Location -Id $Id
    New-AccessLogFile -LogPath $LogPath -Encoding $encoding
    [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine, $encoding)
}

function Write-SseText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Flush()
}

function Add-SseClient {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    [System.Threading.Monitor]::Enter($script:SseClientsLock)

    try {
        [void]$script:SseClients.Add($Response)
    }
    finally {
        [System.Threading.Monitor]::Exit($script:SseClientsLock)
    }
}

function Remove-SseClient {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    [System.Threading.Monitor]::Enter($script:SseClientsLock)

    try {
        [void]$script:SseClients.Remove($Response)
    }
    finally {
        [System.Threading.Monitor]::Exit($script:SseClientsLock)
    }

    try {
        if ($Response.OutputStream.CanWrite) {
            $Response.OutputStream.Close()
        }
    }
    catch {
    }

    try {
        $Response.Close()
    }
    catch {
    }
}

function Get-SseClientsSnapshot {
    [System.Threading.Monitor]::Enter($script:SseClientsLock)

    try {
        return @($script:SseClients.ToArray())
    }
    finally {
        [System.Threading.Monitor]::Exit($script:SseClientsLock)
    }
}

function Send-AccessEvent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $clients = @(Get-SseClientsSnapshot)
    if ($clients.Count -eq 0) {
        return
    }

    $payload = @{
        time = [DateTime]::UtcNow.ToString('o')
        type = $Type
        location = $Location
        id = $Id
    } | ConvertTo-Json -Compress
    $message = "event: access`ndata: $payload`n`n"

    foreach ($client in $clients) {
        try {
            Write-SseText -Response $client -Text $message
        }
        catch {
            Remove-SseClient -Response $client
        }
    }
}

function Invoke-EventRoute {
    param(
        $req,
        $res
    )

    $rawResponse = $res.Context.Response
    $rawResponse.StatusCode = 200
    $rawResponse.ContentType = 'text/event-stream; charset=utf-8'
    $rawResponse.KeepAlive = $true
    $rawResponse.SendChunked = $true
    $rawResponse.Headers['Cache-Control'] = 'no-cache'

    try {
        Write-SseText -Response $rawResponse -Text ": connected`n`n"
        Add-SseClient -Response $rawResponse
        $res.IsSent = $true
    }
    catch {
        try {
            $rawResponse.Close()
        }
        catch {
        }
    }
}

function Invoke-CreateMemberRoute {
    param($req, $res)

    $payload = Read-JsonPayload -Request $req -Response $res
    if ($null -eq $payload) {
        return
    }

    $id = Get-StringField -Object $payload -Name 'id'
    $name = Get-StringField -Object $payload -Name 'name'
    $unit = Get-StringField -Object $payload -Name 'unit'
    if ((Test-Blank $id) -or (Test-Blank $name) -or (Test-Blank $unit)) {
        Send-RejectedResponse -Response $res -Message 'id, name, unit are required'
        return
    }

    $members = (Import-Members).Members
    if ($null -ne (Find-MemberById -Members $members -Id $id)) {
        Send-RejectedResponse -Response $res -Message 'id already exists'
        return
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
    }
    catch {
        Send-RejectedResponse -Response $res -Message 'failed to write list' -StatusCode 500
        return
    }

    Sync-MemberCaches -Members $nextMembers -AllowedIds $script:AllowedIds -SerialToMember $script:SerialToMember
    $null = $res.Json(@{ status = 'created'; member = $newMember })
}

function Invoke-UpdateMemberRoute {
    param($req, $res)

    $payload = Read-JsonPayload -Request $req -Response $res
    if ($null -eq $payload) {
        return
    }

    $id = Get-StringField -Object $payload -Name 'id'
    $name = Get-StringField -Object $payload -Name 'name'
    $unit = Get-StringField -Object $payload -Name 'unit'
    if ((Test-Blank $id) -or (Test-Blank $name) -or (Test-Blank $unit)) {
        Send-RejectedResponse -Response $res -Message 'id, name, unit are required'
        return
    }

    $members = (Import-Members).Members
    $target = Find-MemberById -Members $members -Id $id
    if ($null -eq $target) {
        Send-RejectedResponse -Response $res -Message 'id not found' -StatusCode 404
        return
    }

    Set-MemberField -Member $target -Name 'name' -Value $name
    Set-MemberField -Member $target -Name 'unit' -Value $unit

    try {
        Save-Members -Members $members
    }
    catch {
        Send-RejectedResponse -Response $res -Message 'failed to write list' -StatusCode 500
        return
    }

    Sync-MemberCaches -Members $members -AllowedIds $script:AllowedIds -SerialToMember $script:SerialToMember
    $null = $res.Json(@{ status = 'updated'; member = $target })
}

function Invoke-DeleteMemberRoute {
    param($req, $res)

    $payload = Read-JsonPayload -Request $req -Response $res
    if ($null -eq $payload) {
        return
    }

    $id = Get-StringField -Object $payload -Name 'id'
    if (Test-Blank $id) {
        Send-RejectedResponse -Response $res -Message 'id is required'
        return
    }

    $members = (Import-Members).Members
    $nextMembers = @()
    $removed = $false

    foreach ($member in $members) {
        if ((Get-StringField -Object $member -Name 'id') -eq $id) {
            $removed = $true
            continue
        }

        $nextMembers += $member
    }

    if (-not $removed) {
        Send-RejectedResponse -Response $res -Message 'id not found' -StatusCode 404
        return
    }

    try {
        Save-Members -Members $nextMembers
    }
    catch {
        Send-RejectedResponse -Response $res -Message 'failed to write list' -StatusCode 500
        return
    }

    Sync-MemberCaches -Members $nextMembers -AllowedIds $script:AllowedIds -SerialToMember $script:SerialToMember
    $null = $res.Json(@{ status = 'deleted'; id = $id })
}

function Invoke-ReissueMemberRoute {
    param($req, $res)

    $payload = Read-JsonPayload -Request $req -Response $res
    if ($null -eq $payload) {
        return
    }

    $id = Get-StringField -Object $payload -Name 'id'
    if (Test-Blank $id) {
        Send-RejectedResponse -Response $res -Message 'id is required'
        return
    }

    $members = (Import-Members).Members
    $target = Find-MemberById -Members $members -Id $id
    if ($null -eq $target) {
        Send-RejectedResponse -Response $res -Message 'id not found' -StatusCode 404
        return
    }

    Set-MemberField -Member $target -Name 'serial' -Value (New-MemberSerial -Members $members -ExcludeId $id)
    Set-MemberField -Member $target -Name 'serialLastReissuedAtKst' -Value (Get-KstNowText)

    try {
        Save-Members -Members $members
    }
    catch {
        Send-RejectedResponse -Response $res -Message 'failed to write list' -StatusCode 500
        return
    }

    Sync-MemberCaches -Members $members -AllowedIds $script:AllowedIds -SerialToMember $script:SerialToMember
    $null = $res.Json(@{ status = 'reissued'; member = $target })
}

function Invoke-AccessRoute {
    param($req, $res)

    $payload = Read-JsonPayload -Request $req -Response $res
    if ($null -eq $payload) {
        return
    }

    $type = Get-StringField -Object $payload -Name 'type'
    $location = Get-StringField -Object $payload -Name 'location'
    $serial = Get-StringField -Object $payload -Name 'serial'

    if ((Test-Blank $type) -or (Test-Blank $location) -or (Test-Blank $serial)) {
        Send-RejectedResponse -Response $res -Message 'type, serial, location are required'
        return
    }

    if ($type -ne 'entry' -and $type -ne 'exit') {
        Send-RejectedResponse -Response $res -Message 'type must be entry or exit'
        return
    }

    $member = $script:SerialToMember[$serial]
    if ($null -eq $member) {
        Send-RejectedResponse -Response $res -Message 'serial is not allowed'
        return
    }

    $id = Get-StringField -Object $member -Name 'id'
    if (Test-Blank $id) {
        Send-RejectedResponse -Response $res -Message 'serial is invalid'
        return
    }

    if (-not $script:AllowedIds.ContainsKey($id)) {
        Send-RejectedResponse -Response $res -Message 'id is not allowed'
        return
    }

    try {
        Add-AccessRecord -LogPath $script:LogPath -Type $type -Location $location -Id $id
    }
    catch {
        Send-RejectedResponse -Response $res -Message 'failed to write access record' -StatusCode 500
        return
    }

    Send-AccessEvent -Type $type -Location $location -Id $id
    $null = $res.Json(@{
        status = 'logged'
        id = $id
    })
}

function Invoke-RootRoute {
    param($req, $res)

    Send-TextFile -Response $res -RelativePath 'public/index.html' -ContentType 'text/html; charset=utf-8'
}

function Register-StaticRoutes {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )

    Use-Static $App '/public' './public'
    Use-Static $App '/logs' './logs'
}

function New-AcsApp {
    $app = New-App -Root $script:AppRoot -Name 'acs'

    Register-StaticRoutes -App $app

    Add-Route $app GET '/' ${function:Invoke-RootRoute}
    Add-Route $app GET '/event' ${function:Invoke-EventRoute}
    Add-Route $app POST '/access' ${function:Invoke-AccessRoute}
    Add-Route $app POST '/setting/member/create' ${function:Invoke-CreateMemberRoute}
    Add-Route $app POST '/setting/member/update' ${function:Invoke-UpdateMemberRoute}
    Add-Route $app POST '/setting/member/delete' ${function:Invoke-DeleteMemberRoute}
    Add-Route $app POST '/setting/member/reissue' ${function:Invoke-ReissueMemberRoute}

    Set-NotFoundHandler $app {
        param($req, $res)
        $null = $res.Status(404)
        $null = $res.Text('Not Found')
    }

    Set-ErrorHandler $app {
        param($req, $res, $err)

        if ($res.IsSent) {
            return
        }

        try {
            if ($res.Context.Response.OutputStream.CanWrite) {
                Send-RejectedResponse -Response $res -Message 'internal server error' -StatusCode 500
            }
        }
        catch {
        }
    }

    return $app
}

function Start-AcsApp {
    $script:AppRoot = if (Test-Blank $PSScriptRoot) { (Get-Location).Path } else { $PSScriptRoot }
    $script:LogPath = Join-Path $script:AppRoot 'logs/access-log.csv'
    $script:ListPath = Join-Path $script:AppRoot 'public/list.json'
    $membersData = Import-Members
    $script:AllowedIds = $membersData.AllowedIds
    $script:SerialToMember = $membersData.SerialToMember

    $app = New-AcsApp

    Write-Host ('ACS listening on {0}' -f $script:Prefix)
    Write-Host ('App root: {0}' -f $script:AppRoot)
    Write-Host ('Log path: {0}' -f $script:LogPath)
    Write-Host ('List path: {0}' -f $script:ListPath)

    try {
        Start-App -App $app -Prefix $script:Prefix
    }
    finally {
        $clients = @(Get-SseClientsSnapshot)
        foreach ($client in $clients) {
            Remove-SseClient -Response $client
        }
    }
}

Start-AcsApp
