[CmdletBinding()]
param(
    [int]$Port = 9998,
    [string]$BindAddress = "localhost"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Send-Text {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [string]$Text
    )

    $response = $Context.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = "text/plain; charset=utf-8"
    $response.ContentEncoding = [System.Text.Encoding]::UTF8
    $response.Headers["Access-Control-Allow-Origin"] = "*"
    $response.Headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    $response.Headers["Access-Control-Allow-Headers"] = "Content-Type"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    Close-Response -Response $response
}

$listener = $null
try {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add(("http://{0}:{1}/" -f $BindAddress, $Port))
    $listener.Start()

    [Console]::WriteLine(("tiktok server listening on http://{0}:{1}" -f $BindAddress, $Port))
    [Console]::WriteLine("POST /tiktok with body: tick")

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $path = $request.Url.AbsolutePath.ToLowerInvariant()
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($method -eq "OPTIONS") {
            Send-Text -Context $context -StatusCode 204 -Text ""
            continue
        }

        if ($method -ne "POST" -or $path -ne "/tiktok") {
            Send-Text -Context $context -StatusCode 404 -Text "not found"
            continue
        }

        $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
        try {
            $body = $reader.ReadToEnd()
        }
        finally {
            $reader.Close()
        }

        if ([string]$body -eq "tick") {
            Send-Text -Context $context -StatusCode 200 -Text "tock"
        }
        else {
            Send-Text -Context $context -StatusCode 400 -Text "send tick"
        }
    }
}
catch {
    [Console]::Error.WriteLine(("server error: {0}" -f $_.Exception.Message))
    throw
}
finally {
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
}
