$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'milkit-io.psm1'
Import-Module $modulePath -Force

$root = Join-Path '/tmp' ('milkit-io-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

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

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "$Name expected true."
    }
}

try {
    $store = New-Store -Root $root

    # UTF-8 write/read (default bomless)
    $store.WriteText('plain.txt', 'hello')
    Assert-Eq -Name 'plain text read' -Actual ($store.ReadText('plain.txt')) -Expected 'hello'

    $plainBytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'plain.txt'))
    Assert-True -Name 'plain no bom' -Condition (-not ($plainBytes.Length -ge 3 -and $plainBytes[0] -eq 239 -and $plainBytes[1] -eq 187 -and $plainBytes[2] -eq 191))

    # BOM file compatibility read
    $bomPath = Join-Path $root 'bom.txt'
    [System.IO.File]::WriteAllText($bomPath, '가나다', [System.Text.UTF8Encoding]::new($true))
    Assert-Eq -Name 'bom utf8 read' -Actual ($store.ReadText('bom.txt')) -Expected '가나다'

    # Edit text
    $store.EditText('plain.txt', { param($text) return ($text + '-edited') })
    Assert-Eq -Name 'edit text result' -Actual ($store.ReadText('plain.txt')) -Expected 'hello-edited'

    # Optional BOM write
    $storeBom = New-Store -Root $root -WriteBom $true
    $storeBom.WriteText('with-bom.txt', 'abc')
    $withBomBytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'with-bom.txt'))
    Assert-True -Name 'with bom bytes' -Condition ($withBomBytes.Length -ge 3 -and $withBomBytes[0] -eq 239 -and $withBomBytes[1] -eq 187 -and $withBomBytes[2] -eq 191)

    # CSV query DSL (insert auto-create)
    $insertOne = $store.From('access_log').Insert(([ordered]@{
        time = 't1'
        type = 'entry'
        location = 'gate-1'
        id = 'id-1'
    }))
    Assert-Eq -Name 'insert one count' -Actual $insertOne -Expected 1

    $insertTwo = $store.From('access_log').Insert(([ordered]@{
        time = 't2'
        type = 'exit'
        location = 'gate-1'
        id = 'id-1'
    }))
    Assert-Eq -Name 'insert two count' -Actual $insertTwo -Expected 1

    $insertThree = $store.From('access_log').Insert(([ordered]@{
        time = 't3'
        type = 'entry'
        location = 'gate-2'
        id = 'id-2'
    }))
    Assert-Eq -Name 'insert three count' -Actual $insertThree -Expected 1

    $entryRows = @($store.From('access_log').Where(@{ type = 'entry' }).Find())
    Assert-Eq -Name 'entry rows count' -Actual $entryRows.Count -Expected 2

    $andRows = @($store.From('access_log').Where(@{ type = 'entry'; id = 'id-2' }).Select(@('id', 'location')).Find())
    Assert-Eq -Name 'and where count' -Actual $andRows.Count -Expected 1
    Assert-Eq -Name 'and where id' -Actual $andRows[0].id -Expected 'id-2'
    Assert-Eq -Name 'and where location' -Actual $andRows[0].location -Expected 'gate-2'

    $updated = $store.From('access_log').Where(@{ type = 'entry' }).Update(@{ location = 'gate-9' })
    Assert-Eq -Name 'update affected count' -Actual $updated -Expected 2

    $selected = @($store.From('access_log').Where(@{ location = 'gate-9' }).Select(@('id', 'location')).Find())
    Assert-Eq -Name 'selected count' -Actual $selected.Count -Expected 2

    $deletedExit = $store.From('access_log').Where(@{ type = 'exit' }).Delete()
    Assert-Eq -Name 'delete exit count' -Actual $deletedExit -Expected 1

    $deletedEntry = $store.From('access_log').Where(@{ type = 'entry' }).Delete()
    Assert-Eq -Name 'delete entry count' -Actual $deletedEntry -Expected 2

    $afterDelete = @($store.From('access_log').Find())
    Assert-Eq -Name 'rows after delete' -Actual $afterDelete.Count -Expected 0

    # Missing file behavior for update/delete/find
    Assert-Eq -Name 'missing find count' -Actual (@($store.From('no_file').Find()).Count) -Expected 0
    Assert-Eq -Name 'missing update count' -Actual ($store.From('no_file').Where(@{ id = 'x' }).Update(@{ id = 'y' })) -Expected 0
    Assert-Eq -Name 'missing delete count' -Actual ($store.From('no_file').Where(@{ id = 'x' }).Delete()) -Expected 0

    'OK'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
