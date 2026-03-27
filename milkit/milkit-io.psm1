function Resolve-StoreRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        throw 'Root cannot be empty.'
    }

    if ([System.IO.Path]::IsPathRooted($Root)) {
        return [System.IO.Path]::GetFullPath($Root)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Root))
}

function Test-FlatName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name -eq '.' -or $Name -eq '..') {
        return $false
    }

    return ($Name.IndexOfAny(@([char]'/', [char]'\')) -lt 0)
}

function Resolve-StoreFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    if (-not (Test-FlatName -Name $FileName)) {
        throw 'FileName must be a flat name without path separators.'
    }

    return (Join-Path $Store.Root $FileName)
}

function Resolve-StoreTablePath {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    if (-not (Test-FlatName -Name $TableName)) {
        throw 'TableName must be a flat name without path separators.'
    }

    return (Join-Path $Store.Root ($TableName + '.csv'))
}

function Get-StoreEncoding {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store
    )

    return [System.Text.UTF8Encoding]::new([bool]$Store.WriteBom)
}

function Read-TextUtf8Auto {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        $Text = ''
    }

    [System.IO.File]::WriteAllText($Path, $Text, (Get-StoreEncoding -Store $Store))
}

function Escape-CsvField {
    param(
        [AllowNull()]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ($text.Contains('"')) {
        $text = $text.Replace('"', '""')
    }

    if ($text.Contains(',') -or $text.Contains('"') -or $text.Contains("`r") -or $text.Contains("`n")) {
        return '"' + $text + '"'
    }

    return $text
}

function Parse-CsvHeaderLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HeaderLine
    )

    if ([string]::IsNullOrWhiteSpace($HeaderLine)) {
        return @()
    }

    $parts = @()
    foreach ($item in $HeaderLine.Split(',')) {
        $value = $item.Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2).Replace('""', '"')
        }

        $parts += $value
    }

    return $parts
}

function Read-CsvTable {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    $path = Resolve-StoreTablePath -Store $Store -TableName $TableName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $path
            Exists  = $false
            Headers = @()
            Rows    = @()
        }
    }

    $text = Read-TextUtf8Auto -Path $path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{
            Path    = $path
            Exists  = $true
            Headers = @()
            Rows    = @()
        }
    }

    $lines = $text -split "`r?`n"
    $headerLine = ''
    if ($lines.Count -gt 0) {
        $headerLine = $lines[0]
    }

    $headers = Parse-CsvHeaderLine -HeaderLine $headerLine
    $rows = @()

    try {
        $rows = @($text | ConvertFrom-Csv)
    }
    catch {
        throw "Invalid CSV file: $path"
    }

    return [pscustomobject]@{
        Path    = $path
        Exists  = $true
        Headers = $headers
        Rows    = $rows
    }
}

function Build-OrderedRow {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Headers,

        [Parameter(Mandatory = $true)]
        [AllowNull()]$Source
    )

    $ordered = [ordered]@{}
    foreach ($column in $Headers) {
        $value = ''
        if ($null -ne $Source) {
            if ($Source -is [System.Collections.IDictionary]) {
                foreach ($key in $Source.Keys) {
                    if ([string]$key -ne $column) {
                        continue
                    }

                    $value = [string]$Source[$key]
                    break
                }
            }
            else {
                $property = $Source.PSObject.Properties[$column]
                if ($null -ne $property) {
                    $value = [string]$property.Value
                }
            }
        }

        $ordered[$column] = $value
    }

    return [pscustomobject]$ordered
}

function Write-CsvTable {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Headers,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    if ($Headers.Count -eq 0) {
        Write-TextUtf8 -Store $Store -Path $Path -Text ''
        return
    }

    if ($Rows.Count -eq 0) {
        $headerText = [string]::Join(',', ($Headers | ForEach-Object { Escape-CsvField -Value $_ }))
        Write-TextUtf8 -Store $Store -Path $Path -Text ($headerText + [Environment]::NewLine)
        return
    }

    $normalizedRows = @()
    foreach ($row in $Rows) {
        $normalizedRows += (Build-OrderedRow -Headers $Headers -Source $row)
    }

    $csvLines = @($normalizedRows | ConvertTo-Csv -NoTypeInformation)
    $csvText = [string]::Join([Environment]::NewLine, $csvLines) + [Environment]::NewLine
    Write-TextUtf8 -Store $Store -Path $Path -Text $csvText
}

function Test-RowMatch {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,

        [hashtable]$Where
    )

    if ($null -eq $Where -or $Where.Count -eq 0) {
        return $true
    }

    foreach ($key in $Where.Keys) {
        $property = $Row.PSObject.Properties[[string]$key]
        if ($null -eq $property) {
            return $false
        }

        if ([string]$property.Value -ne [string]$Where[$key]) {
            return $false
        }
    }

    return $true
}

function Get-SelectedHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Query,

        [Parameter(Mandatory = $true)]
        [string[]]$DefaultHeaders
    )

    if ($null -eq $Query.SelectColumns -or $Query.SelectColumns.Count -eq 0) {
        return $DefaultHeaders
    }

    return @($Query.SelectColumns)
}

function Invoke-StoreCsvFind {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Query
    )

    $table = Read-CsvTable -Store $Query.Store -TableName $Query.TableName
    if ($table.Rows.Count -eq 0) {
        return @()
    }

    $selectedHeaders = Get-SelectedHeaders -Query $Query -DefaultHeaders $table.Headers
    $found = @()

    foreach ($row in $table.Rows) {
        if (-not (Test-RowMatch -Row $row -Where $Query.WhereMap)) {
            continue
        }

        $found += (Build-OrderedRow -Headers $selectedHeaders -Source $row)
    }

    return $found
}

function Invoke-StoreCsvInsert {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )

    if ($Values.Count -eq 0) {
        throw 'Insert values cannot be empty.'
    }

    $table = Read-CsvTable -Store $Query.Store -TableName $Query.TableName
    $headers = @($table.Headers)

    if ($headers.Count -eq 0) {
        $headers = @()
        foreach ($key in $Values.Keys) {
            $headers += [string]$key
        }
    }

    $rows = @($table.Rows)
    $rows += (Build-OrderedRow -Headers $headers -Source $Values)

    Write-CsvTable -Store $Query.Store -Path $table.Path -Headers $headers -Rows $rows
    return 1
}

function Invoke-StoreCsvUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )

    if ($Values.Count -eq 0) {
        return 0
    }

    $table = Read-CsvTable -Store $Query.Store -TableName $Query.TableName
    if (-not $table.Exists -or $table.Rows.Count -eq 0) {
        return 0
    }

    $affected = 0
    foreach ($row in $table.Rows) {
        if (-not (Test-RowMatch -Row $row -Where $Query.WhereMap)) {
            continue
        }

        foreach ($column in $table.Headers) {
            $hasValue = $false
            $nextValue = ''
            foreach ($key in $Values.Keys) {
                if ([string]$key -ne $column) {
                    continue
                }

                $hasValue = $true
                $nextValue = [string]$Values[$key]
                break
            }

            if (-not $hasValue) {
                continue
            }

            $row.$column = $nextValue
        }

        $affected++
    }

    if ($affected -gt 0) {
        Write-CsvTable -Store $Query.Store -Path $table.Path -Headers $table.Headers -Rows $table.Rows
    }

    return $affected
}

function Invoke-StoreCsvDelete {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Query
    )

    $table = Read-CsvTable -Store $Query.Store -TableName $Query.TableName
    if (-not $table.Exists -or $table.Rows.Count -eq 0) {
        return 0
    }

    $kept = @()
    $affected = 0
    foreach ($row in $table.Rows) {
        if (Test-RowMatch -Row $row -Where $Query.WhereMap) {
            $affected++
            continue
        }

        $kept += $row
    }

    if ($affected -gt 0) {
        Write-CsvTable -Store $Query.Store -Path $table.Path -Headers $table.Headers -Rows $kept
    }

    return $affected
}

function New-StoreCsvQuery {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    $query = [pscustomobject]@{
        Store         = $Store
        TableName     = $TableName
        WhereMap      = @{}
        SelectColumns = @()
    }

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Select -Value {
        param([string[]]$Columns)
        $this.SelectColumns = @($Columns)
        return $this
    } -Force

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Where -Value {
        param([hashtable]$Conditions)
        if ($null -eq $Conditions) {
            $this.WhereMap = @{}
        }
        else {
            $this.WhereMap = $Conditions
        }

        return $this
    } -Force

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Find -Value {
        return (Invoke-StoreCsvFind -Query $this)
    } -Force

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Insert -Value {
        param([hashtable]$Values)
        return (Invoke-StoreCsvInsert -Query $this -Values $Values)
    } -Force

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Update -Value {
        param([hashtable]$Values)
        return (Invoke-StoreCsvUpdate -Query $this -Values $Values)
    } -Force

    Add-Member -InputObject $query -MemberType ScriptMethod -Name Delete -Value {
        return (Invoke-StoreCsvDelete -Query $this)
    } -Force

    return $query
}

function New-Store {
    [CmdletBinding()]
    param(
        [string]$Root,
        [bool]$WriteBom = $false
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $resolvedRoot = Resolve-StoreRoot -Root (Get-Location).Path
    }
    else {
        $resolvedRoot = Resolve-StoreRoot -Root $Root
    }

    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $resolvedRoot -Force)
    }

    $store = [pscustomobject]@{
        Root     = $resolvedRoot
        WriteBom = $WriteBom
    }

    Add-Member -InputObject $store -MemberType ScriptMethod -Name ReadText -Value {
        param([string]$FileName)
        $path = Resolve-StoreFilePath -Store $this -FileName $FileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "File not found: $FileName"
        }

        return (Read-TextUtf8Auto -Path $path)
    } -Force

    Add-Member -InputObject $store -MemberType ScriptMethod -Name WriteText -Value {
        param([string]$FileName, [AllowNull()][string]$Text)
        $path = Resolve-StoreFilePath -Store $this -FileName $FileName
        Write-TextUtf8 -Store $this -Path $path -Text $Text
        return $null
    } -Force

    Add-Member -InputObject $store -MemberType ScriptMethod -Name EditText -Value {
        param([string]$FileName, [scriptblock]$Transform)
        if ($null -eq $Transform) {
            throw 'Transform is required.'
        }

        $path = Resolve-StoreFilePath -Store $this -FileName $FileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "File not found: $FileName"
        }

        $current = Read-TextUtf8Auto -Path $path
        $next = & $Transform $current
        Write-TextUtf8 -Store $this -Path $path -Text ([string]$next)
        return $null
    } -Force

    Add-Member -InputObject $store -MemberType ScriptMethod -Name From -Value {
        param([string]$TableName)
        return (New-StoreCsvQuery -Store $this -TableName $TableName)
    } -Force

    return $store
}

Export-ModuleMember -Function New-Store
