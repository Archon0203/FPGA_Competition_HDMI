$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tdRoot = 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'
$tdBin = Join-Path $tdRoot 'bin'
$tdExe = Join-Path $tdBin 'td_commands_prompt.exe'
$flowTcl = (Join-Path $tdRoot 'doc\scripts\DefaultFlow.tcl').Replace('\','/')
$runRoot = Join-Path $repo 'M1A_Timing_Runs'
$synDir = Join-Path $runRoot 'syn_1'
$phyDir = Join-Path $runRoot 'phy_1'
foreach ($required in @($tdExe, $flowTcl)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "TD file not found: $required" }
}
New-Item -ItemType Directory -Force -Path $synDir, $phyDir | Out-Null

function Write-RunConfig([string]$dir, [string]$type, [string]$start, [string]$end) {
    $cfg = @"
set SDCList {"../../validation/M1A_timing.sdc"}
set area_option -packarea
set arr_filter false
set device_name eagle_s20.db
set drHoldFix on
set package_name EG4S20BG256
set prj_name {M1A_Timing}
set run_type $type
set start_step $start
set end_step $end
set top_model_name {m1a_validation_top}
"@
    Set-Content -LiteralPath (Join-Path $dir 'settings.cfg') -Value $cfg -Encoding Ascii
    $runBat = @"
@echo off
cd /d "$dir"
"$tdExe" "$flowTcl"
"@
    Set-Content -LiteralPath (Join-Path $dir 'run.bat') -Value $runBat -Encoding Ascii
}

function Write-GeneratedProject([string]$dir) {
    [xml]$project = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'M1A_Timing.al') -Raw
    $project.Project.Source_Files.Verilog.File | ForEach-Object {
        $_.Path = '../../' + $_.Path.Substring(3)
    }
    $project.Project.Source_Files.SDC_FILE.File.Path = '../../validation/M1A_timing.sdc'
    $project.Project.SetAttribute('Path', $repo.Replace('\','/'))
    $project.Project.SetAttribute('RunTime', (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'))
    $project.Save((Join-Path $dir 'M1A_Timing.prj'))
}

Write-GeneratedProject $synDir
Write-GeneratedProject $phyDir
Write-RunConfig $synDir 'syn' 'read_design' 'opt_gate'
Write-RunConfig $phyDir 'phy' 'opt_place' 'opt_route'
(Get-Content (Join-Path $phyDir 'settings.cfg') -Raw) + "`nset parent ../syn_1`n" | Set-Content (Join-Path $phyDir 'settings.cfg') -Encoding Ascii

foreach ($dir in @($synDir, $phyDir)) {
    Push-Location $dir
    try {
        & $tdExe $flowTcl
        if ($LASTEXITCODE -ne 0) { throw "TD flow failed in $dir (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
}

$timing = Join-Path $phyDir 'M1A_Timing_pr.timing'
if (-not (Test-Path -LiteralPath (Join-Path $phyDir 'route_flow.status'))) {
    throw "TD route stage did not complete: $(Join-Path $phyDir 'route_flow.status') is missing. Inspect the TD log in $phyDir."
}
if (-not (Test-Path -LiteralPath $timing)) { throw "TD route timing report not found: $timing" }
Write-Host "TD M1A implementation complete. Timing report: $timing"
