function Resolve-AppPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath($Path)
}

function Normalize-RoutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $value = $Path.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw 'Path cannot be empty.'
    }

    if (-not $value.StartsWith('/')) {
        $value = '/' + $value
    }

    if ($value.Length -gt 1 -and $value.EndsWith('/')) {
        $value = $value.TrimEnd('/')
    }

    return $value
}

function Normalize-RoutePrefix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    return Normalize-RoutePath -Path $Prefix
}

function Resolve-HandlerScript {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Handler,

        [string]$ArgumentName = 'Handler'
    )

    if ($Handler -is [scriptblock]) {
        return $Handler
    }

    if ($Handler -is [System.Management.Automation.FunctionInfo]) {
        return $Handler.ScriptBlock
    }

    if ($Handler -is [string]) {
        $command = Get-Command -Name $Handler -CommandType Function -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.ScriptBlock
        }
    }

    throw "$ArgumentName must be a scriptblock or function reference."
}

function Get-ContentTypeByPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.js' { return 'application/javascript; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.txt' { return 'text/plain; charset=utf-8' }
        '.svg' { return 'image/svg+xml' }
        '.png' { return 'image/png' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.gif' { return 'image/gif' }
        '.ico' { return 'image/x-icon' }
        '.woff' { return 'font/woff' }
        '.woff2' { return 'font/woff2' }
        default { return 'application/octet-stream' }
    }
}

function Write-ResponseBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$ContentType,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function New-RequestWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    $bodyText = ''
    if ($Request.HasEntityBody) {
        $encoding = $Request.ContentEncoding
        if ($null -eq $encoding) {
            $encoding = [System.Text.Encoding]::UTF8
        }

        $reader = New-Object System.IO.StreamReader($Request.InputStream, $encoding)
        try {
            $bodyText = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }

    $req = [pscustomobject]@{
        Method       = $Request.HttpMethod.ToUpperInvariant()
        Path         = Normalize-RoutePath -Path $Request.Url.AbsolutePath
        RawPath      = $Request.Url.AbsolutePath
        RawUrl       = $Request.RawUrl
        Headers      = $Request.Headers
        Query        = $Request.QueryString
        BodyText     = $bodyText
        __JsonParsed = $false
        __JsonValue  = $null
    }

    Add-Member -InputObject $req -MemberType ScriptMethod -Name Json -Value {
        if (-not $this.__JsonParsed) {
            $this.__JsonParsed = $true
            if ([string]::IsNullOrWhiteSpace($this.BodyText)) {
                $this.__JsonValue = $null
            }
            else {
                $this.__JsonValue = $this.BodyText | ConvertFrom-Json
            }
        }

        return $this.__JsonValue
    } -Force

    return $req
}

function New-ResponseWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context
    )

    $res = [pscustomobject]@{
        Context    = $Context
        StatusCode = 200
        IsSent     = $false
    }

    Add-Member -InputObject $res -MemberType ScriptMethod -Name Status -Value {
        param([int]$Code)
        $this.StatusCode = $Code
        return $this
    } -Force

    Add-Member -InputObject $res -MemberType ScriptMethod -Name Text -Value {
        param(
            [AllowNull()]
            [string]$Text,

            [string]$ContentType = 'text/plain; charset=utf-8'
        )

        if ($this.IsSent) {
            return $null
        }

        if ($null -eq $Text) {
            $Text = ''
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        Write-ResponseBytes -Response $this.Context.Response -Bytes $bytes -ContentType $ContentType -StatusCode $this.StatusCode
        $this.IsSent = $true
        return $null
    } -Force

    Add-Member -InputObject $res -MemberType ScriptMethod -Name Json -Value {
        param([AllowNull()]$Data)

        if ($this.IsSent) {
            return $null
        }

        $json = $Data | ConvertTo-Json -Depth 20 -Compress
        $null = $this.Text($json, 'application/json; charset=utf-8')
        return $null
    } -Force

    Add-Member -InputObject $res -MemberType ScriptMethod -Name Ok -Value {
        param([AllowNull()]$Data)
        $null = $this.Status(200)
        $null = $this.Json($Data)
        return $null
    } -Force

    Add-Member -InputObject $res -MemberType ScriptMethod -Name NotFound -Value {
        param([AllowNull()]$Data)
        $null = $this.Status(404)
        $null = $this.Json($Data)
        return $null
    } -Force

    Add-Member -InputObject $res -MemberType ScriptMethod -Name InternalServerError -Value {
        param([AllowNull()]$Data)
        $null = $this.Status(500)
        $null = $this.Json($Data)
        return $null
    } -Force

    return $res
}

function Invoke-AutoResponse {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [AllowNull()]$Value
    )

    if ($Response.IsSent) {
        return
    }

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [string]) {
        $null = $Response.Text([string]$Value)
        return
    }

    $null = $Response.Json($Value)
}

function Test-PrefixMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ($Prefix -eq '/') {
        return $true
    }

    if ($Path -eq $Prefix) {
        return $true
    }

    return $Path.StartsWith($Prefix + '/')
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $root = Resolve-AppPath -Path $RootPath
    $target = Resolve-AppPath -Path $TargetPath
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if ($target.Equals($root, $comparison)) {
        return $true
    }

    $rootWithSeparator = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    return $target.StartsWith($rootWithSeparator, $comparison)
}

function Send-FileResponse {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if ($Response.IsSent) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-ResponseBytes -Response $Response.Context.Response -Bytes $bytes -ContentType (Get-ContentTypeByPath -Path $FilePath) -StatusCode $Response.StatusCode
    $Response.IsSent = $true
}

function Find-RouteMatch {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [psobject]$Request
    )

    foreach ($route in $App.Routes) {
        if ($route.Path -ne $Request.Path) {
            continue
        }

        if ($route.Methods -contains '*') {
            return $route
        }

        if ($route.Methods -contains $Request.Method) {
            return $route
        }
    }

    return $null
}

function Try-ServeStatic {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [Parameter(Mandatory = $true)]
        [psobject]$Response
    )

    foreach ($rule in $App.StaticRules) {
        if (-not (Test-PrefixMatch -Path $Request.Path -Prefix $rule.Prefix)) {
            continue
        }

        $relative = $Request.Path.Substring($rule.Prefix.Length)
        if ($relative.StartsWith('/')) {
            $relative = $relative.Substring(1)
        }

        $relative = [System.Uri]::UnescapeDataString($relative)
        $relative = $relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar

        $candidate = Resolve-AppPath -Path (Join-Path $rule.RootPath $relative)
        if (-not (Test-PathUnderRoot -RootPath $rule.RootPath -TargetPath $candidate)) {
            $null = $Response.NotFound(@{ message = 'not found' })
            return $true
        }

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Send-FileResponse -Response $Response -FilePath $candidate
            return $true
        }

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            foreach ($document in $rule.DefaultDocuments) {
                $defaultPath = Resolve-AppPath -Path (Join-Path $candidate $document)
                if (-not (Test-PathUnderRoot -RootPath $rule.RootPath -TargetPath $defaultPath)) {
                    continue
                }

                if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
                    Send-FileResponse -Response $Response -FilePath $defaultPath
                    return $true
                }
            }
        }

        return $false
    }

    return $false
}

function Invoke-Endpoint {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [Parameter(Mandatory = $true)]
        [psobject]$Response
    )

    $route = Find-RouteMatch -App $App -Request $Request
    if ($null -ne $route) {
        return & $route.Handler $Request $Response
    }

    $served = Try-ServeStatic -App $App -Request $Request -Response $Response
    if ($served) {
        return $null
    }

    return & $App.NotFoundHandler $Request $Response
}

function Invoke-MiddlewareStep {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if ($Response.IsSent) {
        return $null
    }

    if ($Index -ge $App.Middlewares.Count) {
        return Invoke-Endpoint -App $App -Request $Request -Response $Response
    }

    $middleware = $App.Middlewares[$Index]
    $nextCalled = $false
    $invokeStep = ${function:Invoke-MiddlewareStep}

    $next = {
        if ($nextCalled) {
            return $null
        }

        $nextCalled = $true
        return & $invokeStep -App $App -Request $Request -Response $Response -Index ($Index + 1)
    }.GetNewClosure()

    return & $middleware $Request $Response $next
}

function Invoke-RequestPipeline {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [Parameter(Mandatory = $true)]
        [psobject]$Response
    )

    return Invoke-MiddlewareStep -App $App -Request $Request -Response $Response -Index 0
}

function Invoke-RequestContext {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context
    )

    $request = New-RequestWrapper -Request $Context.Request
    $response = New-ResponseWrapper -Context $Context

    try {
        $result = Invoke-RequestPipeline -App $App -Request $request -Response $response
        Invoke-AutoResponse -Response $response -Value $result

        if (-not $response.IsSent) {
            $null = $response.InternalServerError(@{ message = 'internal server error' })
        }
    }
    catch {
        try {
            $errorResult = & $App.ErrorHandler $request $response $_
            Invoke-AutoResponse -Response $response -Value $errorResult
            if (-not $response.IsSent) {
                $null = $response.InternalServerError(@{ message = 'internal server error' })
            }
        }
        catch {
            if (-not $response.IsSent) {
                try {
                    $null = $response.InternalServerError(@{ message = 'internal server error' })
                }
                catch {
                }
            }
        }
    }
}

function New-App {
    [CmdletBinding()]
    param(
        [string]$Root,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $resolvedRoot = Resolve-AppPath -Path (Get-Location).Path
    }
    else {
        if ([System.IO.Path]::IsPathRooted($Root)) {
            $resolvedRoot = Resolve-AppPath -Path $Root
        }
        else {
            $resolvedRoot = Resolve-AppPath -Path (Join-Path (Get-Location).Path $Root)
        }
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = 'app'
    }

    $app = [pscustomobject]@{
        Name            = $Name
        Root            = $resolvedRoot
        Routes          = @()
        StaticRules     = @()
        Middlewares     = @()
        NotFoundHandler = $null
        ErrorHandler    = $null
        Listener        = $null
        IsRunning       = $false
    }

    $app.NotFoundHandler = {
        param($req, $res)
        $null = $res.NotFound(@{ message = 'not found' })
    }

    $app.ErrorHandler = {
        param($req, $res, $err)
        $null = $res.InternalServerError(@{ message = 'internal server error' })
    }

    return $app
}

function Add-Route {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [psobject]$App,

        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$Method,

        [Parameter(Mandatory = $true, Position = 2)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 3)]
        [object]$Handler
    )

    $allowedMethods = @('GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS', '*')
    $methods = @()

    foreach ($item in $Method) {
        $value = $item.Trim().ToUpperInvariant()
        if ($allowedMethods -notcontains $value) {
            throw "Unsupported HTTP method: $item"
        }

        if ($methods -notcontains $value) {
            $methods += $value
        }
    }

    $route = [pscustomobject]@{
        Methods = $methods
        Path    = Normalize-RoutePath -Path $Path
        Handler = Resolve-HandlerScript -Handler $Handler
    }

    $App.Routes = @($App.Routes + $route)
}

function Use-Static {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [psobject]$App,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Prefix,

        [Parameter(Mandatory = $true, Position = 2)]
        [string]$Path,

        [string[]]$DefaultDocument = @('index.html')
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = Resolve-AppPath -Path $Path
    }
    else {
        $resolvedPath = Resolve-AppPath -Path (Join-Path $App.Root $Path)
    }

    $documents = @()
    foreach ($item in $DefaultDocument) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $documents += $item
        }
    }

    if ($documents.Count -eq 0) {
        $documents = @('index.html')
    }

    $rule = [pscustomobject]@{
        Prefix           = Normalize-RoutePrefix -Prefix $Prefix
        RootPath         = $resolvedPath
        DefaultDocuments = $documents
    }

    $App.StaticRules = @($App.StaticRules + $rule)
}

function Use {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [psobject]$App,

        [Parameter(Mandatory = $true, Position = 1)]
        [object]$Handler
    )

    $resolvedHandler = Resolve-HandlerScript -Handler $Handler
    $App.Middlewares = @($App.Middlewares + $resolvedHandler)
}

function Set-NotFoundHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [object]$Handler
    )

    $App.NotFoundHandler = Resolve-HandlerScript -Handler $Handler
}

function Set-ErrorHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $true)]
        [object]$Handler
    )

    $App.ErrorHandler = Resolve-HandlerScript -Handler $Handler
}

function Start-App {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [int]$Port = 8080,

        [string]$BindHost = 'localhost',

        [string[]]$Prefix
    )

    if ($App.IsRunning) {
        throw 'App is already running.'
    }

    $listener = New-Object System.Net.HttpListener

    $prefixes = @()
    if ($null -ne $Prefix -and $Prefix.Count -gt 0) {
        $prefixes = $Prefix
    }
    else {
        $prefixes = @("http://$BindHost`:$Port/")
    }

    foreach ($item in $prefixes) {
        $value = $item.Trim()
        if (-not $value.EndsWith('/')) {
            $value = $value + '/'
        }

        $listener.Prefixes.Add($value)
    }

    $App.Listener = $listener
    $App.IsRunning = $true

    try {
        $listener.Start()
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
            }
            catch {
                if (-not $listener.IsListening) {
                    break
                }

                throw
            }

            Invoke-RequestContext -App $App -Context $context
        }
    }
    finally {
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

        $App.Listener = $null
        $App.IsRunning = $false
    }
}

function Stop-App {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )

    if ($null -eq $App.Listener) {
        $App.IsRunning = $false
        return
    }

    try {
        if ($App.Listener.IsListening) {
            $App.Listener.Stop()
        }
    }
    finally {
        try {
            $App.Listener.Close()
        }
        catch {
        }

        $App.Listener = $null
        $App.IsRunning = $false
    }
}

Export-ModuleMember -Function New-App, Start-App, Stop-App, Add-Route, Use-Static, Use, Set-NotFoundHandler, Set-ErrorHandler
