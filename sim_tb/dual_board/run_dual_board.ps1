$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$questa = 'D:\Questasim64_10.7c\win64'
$simRoot = Join-Path $repo 'sim_tb\dual_board'
$work = Join-Path $simRoot 'work'
if (-not (Test-Path (Join-Path $work '_info'))) { & (Join-Path $questa 'vlib.exe') $work }
Push-Location $simRoot
& (Join-Path $questa 'vlog.exe') -work work `
    (Join-Path $repo 'src\dual_board\db_uart_tx.v') `
    (Join-Path $repo 'src\dual_board\db_uart_rx.v') `
    (Join-Path $repo 'src\dual_board\db_frame_parser.v') `
    (Join-Path $repo 'src\dual_board\db_frame_tx.v') `
    (Join-Path $repo 'src\dual_board\db_hex_display.v') `
    (Join-Path $repo 'src\dual_board\db_startup_reset.v') `
    (Join-Path $repo 'src\dual_board\dual_board_master_top.v') `
    (Join-Path $repo 'src\dual_board\dual_board_slave_top.v') `
    (Join-Path $repo 'sim_tb\dual_board\tb_dual_board_uart.v')
if ($LASTEXITCODE -ne 0) { throw 'Questa compilation failed.' }
& (Join-Path $questa 'vsim.exe') -c -lib work tb_dual_board_uart -do 'run -all; quit -f'
if ($LASTEXITCODE -ne 0) { throw 'Dual-board simulation failed.' }
Pop-Location
