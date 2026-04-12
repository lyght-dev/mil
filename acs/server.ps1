Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:AppRoot = ""
$script:LogPath = ""
$script:ListPath = ""
$script:AllowedIds = @{}
$script:SerialToMember = @{}
$script:Prefix = "http://+:8888/"

function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".csv" { return "text/csv; charset=utf-8" }
        ".woff2" { return "font/woff2" }
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
    # PowerShell 5 / HttpListenerResponse 호환 이슈로 ContentLength64는 설정하지 않는다.
    # OutputStream.Close()로 응답 종료는 정상 처리된다.
    # $Response.ContentLength64 = $Bytes.Length
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

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [object]$Payload,

        [int]$StatusCode = 200
    )

    $json = $Payload | ConvertTo-Json -Compress -Depth 8

    Send-TextResponse -Response $Response -Text $json -ContentType "application/json; charset=utf-8" -StatusCode $StatusCode
}

function Send-RejectedResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$StatusCode = 400
    )

    Send-JsonResponse -Response $Response -Payload @{
        status = "rejected"
        message = $Message
    } -StatusCode $StatusCode
}

function Send-InternalServerError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    if ($Response.OutputStream.CanWrite) {
        Send-RejectedResponse -Response $Response -Message "internal server error" -StatusCode 500
    }
}

function Get-RequestBodyText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    $encoding = if ($null -ne $Request.ContentEncoding) { $Request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $encoding)

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
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
        return ""
    }

    return [string]$property.Value
}

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

function New-AccessLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding
    )

    $dir = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    if (-not (Test-Path -LiteralPath $LogPath)) { [System.IO.File]::WriteAllText($LogPath, "time,type,location,id`n", $Encoding) }
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

    return ("{0},{1},{2},{3}" -f [DateTime]::UtcNow.ToString("o"), $Type, $Location, $Id)
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
        "/board.html" { "board.html" }
        "/setting.html" { "setting.html" }
        "/script.js" { "script.js" }
        "/style.css" { "style.css" }
        "/setting.css" { "setting.css" }
        "/setting.js" { "setting.js" }
        "/list.json" { "list.json" }
        "/location.json" { "location.json" }
        "/logs/access-log.csv" { "logs/access-log.csv" }
        "/public/PretendardJP-Regular.woff2" { "public/PretendardJP-Regular.woff2" }
        "/public/PretendardJP-SemiBold.woff2" { "public/PretendardJP-SemiBold.woff2" }
        "/public/PretendardJP-Bold.woff2" { "public/PretendardJP-Bold.woff2" }
        "/public/PretendardJP-ExtraBold.woff2" { "public/PretendardJP-ExtraBold.woff2" }
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

function Invoke-AccessRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$SerialToMember
    )

    $payload = Read-JsonPayload -Request $Request -Response $Response
    if ($null -eq $payload) { return $true }

    $type = Get-StringField -Object $payload -Name "type"
    $location = Get-StringField -Object $payload -Name "location"
    $serial = Get-StringField -Object $payload -Name "serial"

    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($location) -or [string]::IsNullOrWhiteSpace($serial)) {
        Send-RejectedResponse -Response $Response -Message "type, serial, location are required"
        return $true
    }

    if ($type -ne "entry" -and $type -ne "exit") {
        Send-RejectedResponse -Response $Response -Message "type must be entry or exit"
        return $true
    }

    $member = $SerialToMember[$serial]
    if ($null -eq $member) {
        Send-RejectedResponse -Response $Response -Message "serial is not allowed"
        return $true
    }

    $id = Get-StringField -Object $member -Name "id"
    if ([string]::IsNullOrWhiteSpace($id)) {
        Send-RejectedResponse -Response $Response -Message "serial is invalid"
        return $true
    }

    if (-not $AllowedIds.ContainsKey($id)) {
        Send-RejectedResponse -Response $Response -Message "id is not allowed"
        return $true
    }

    try {
        Add-AccessRecord -LogPath $LogPath -Type $type -Location $location -Id $id
    } catch {
        Send-RejectedResponse -Response $Response -Message "failed to write access record" -StatusCode 500
        return $true
    }

    Send-JsonResponse -Response $Response -Payload @{
        status = "logged"
    }
    return $true
}

function Invoke-ApiRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$SerialToMember
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if (Invoke-SettingApiRoute -Context $Context -AllowedIds $AllowedIds -SerialToMember $SerialToMember) { return $true }
    if ($method -eq "POST" -and $path -eq "/access") { return (Invoke-AccessRoute -Request $request -Response $response -LogPath $LogPath -AllowedIds $AllowedIds -SerialToMember $SerialToMember) }

    return $false
}

function Invoke-Request {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds,

        [Parameter(Mandatory = $true)]
        [hashtable]$SerialToMember
    )

    if (Invoke-StaticResourceRoute -Context $Context -AppRoot $AppRoot) { return }
    if (Invoke-ApiRoute -Context $Context -LogPath $LogPath -AllowedIds $AllowedIds -SerialToMember $SerialToMember) { return }
    Send-TextResponse -Response $Context.Response -Text "Not Found" -StatusCode 404
}

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
        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }
}

Start-AcsServer
