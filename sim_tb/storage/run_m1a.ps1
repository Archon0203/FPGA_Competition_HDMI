$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$questaBin = 'D:\Questasim64_10.7c\win64'
$vlog = Join-Path $questaBin 'vlog.exe'
$vsim = Join-Path $questaBin 'vsim.exe'
$simWork = Join-Path $repoRoot 'sim_work'
$storage = Join-Path $repoRoot 'src\storage'

foreach ($tool in @($vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Questa executable not found: $tool" }
}
if (-not (Test-Path -LiteralPath $simWork)) { New-Item -ItemType Directory -Path $simWork | Out-Null }

$sources = @(
    (Join-Path $repoRoot 'src\framebuf\async_fifo.v'),
    (Join-Path $storage 'm1a_spi_slave.v'),
    (Join-Path $storage 'm1a_command_decoder.v'),
    (Join-Path $storage 'm1a_provider_cdc.v'),
    (Join-Path $storage 'm1a_media_service_mock.v'),
    (Join-Path $storage 'm1a_service_shell.v'),
    (Join-Path $storage 'm1a_catalog_table.v'),
    (Join-Path $storage 'fat32_scan.v'),
    (Join-Path $storage 'm1a_fat32_catalog.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_spi_slave.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_command_decoder.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_provider_cdc.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_media_service_mock.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_service_shell.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_catalog_table.v'),
    (Join-Path $PSScriptRoot 'tb_m1a_fat32_catalog.v'),
    (Join-Path $PSScriptRoot 'tb_fat32_scan.v')
)
$tops = @(
    'tb_m1a_spi_slave',
    'tb_m1a_command_decoder',
    'tb_m1a_provider_cdc',
    'tb_m1a_media_service_mock',
    'tb_m1a_service_shell',
    'tb_m1a_catalog_table',
    'tb_m1a_fat32_catalog',
    'tb_fat32_scan'
)

Push-Location $simWork
try {
    if (-not (Test-Path -LiteralPath (Join-Path $simWork 'work'))) {
        & (Join-Path $questaBin 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create Questa work library.' }
    }

    & $vlog -work work "+incdir+$storage" @sources
    if ($LASTEXITCODE -ne 0) { throw 'M1A Questa compilation failed.' }

    foreach ($top in $tops) {
        Write-Host "=== $top ==="
        $output = & $vsim -c -lib work $top -do 'run -all; quit -f' 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        $text = $output -join "`n"
        $passLabel = $top -replace '^tb_', ''
        if ($exitCode -ne 0 -or $text -notmatch "PASS: $passLabel") {
            throw "M1A simulation failed: $top (exit $exitCode)."
        }
    }
    Write-Host 'M1A regression PASS: 8/8 testbenches.'
}
finally {
    Pop-Location
}
