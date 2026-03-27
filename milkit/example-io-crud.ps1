param(
    [string]$StoreRoot = '/tmp/milkit-io-example'
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'milkit-io.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $StoreRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $StoreRoot -Force)
}

$store = New-Store -Root $StoreRoot

# Create
$store.From('access_records').Insert([ordered]@{
    id = 'A-001'
    access_type = 'entry'
    time = '2026-03-27T10:00:00Z'
}) | Out-Null

$store.From('access_records').Insert([ordered]@{
    id = 'A-001'
    access_type = 'exit'
    time = '2026-03-27T18:00:00Z'
}) | Out-Null

# Read
$rows = @(
    $store.From('access_records').
        Where(@{ id = 'A-001'; access_type = 'entry' }).
        Select(@('id', 'access_type', 'time')).
        Find()
)

'READ:'
$rows | ConvertTo-Json -Depth 5

# Update
$updated = $store.From('access_records').
    Where(@{ id = 'A-001'; access_type = 'entry' }).
    Update(@{ time = '2026-03-27T10:05:00Z' })

"UPDATED_COUNT=$updated"

# Delete
$deleted = $store.From('access_records').
    Where(@{ id = 'A-001'; access_type = 'exit' }).
    Delete()

"DELETED_COUNT=$deleted"

'AFTER_DELETE:'
$store.From('access_records').
    Select(@('id', 'access_type', 'time')).
    Find() | ConvertTo-Json -Depth 5
