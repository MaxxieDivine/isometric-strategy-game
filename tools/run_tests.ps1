# Reimports the project (refreshing Godot's global class cache) and runs every
# tests/test_*.gd suite headless. Exits 0 if all pass, 1 if any fail.
#
# Usage:  .\tools\run_tests.ps1            (all suites)
#         .\tools\run_tests.ps1 cities     (only suites whose name contains "cities")

param(
	[string]$Filter = "",
	[string]$Godot = "D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
)

# Godot writes progress to stderr; don't let that abort the script.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
	Write-Host "Godot not found at $Godot" -ForegroundColor Red
	exit 2
}

function Invoke-Godot([string[]]$GodotArgs) {
	# Stringify every line so stderr records print as plain text.
	$lines = & $Godot @GodotArgs 2>&1 | ForEach-Object { "$_" }
	return @{ Code = $LASTEXITCODE; Lines = $lines }
}

$scriptErrorPattern = "SCRIPT ERROR|Parse Error|Failed to load script"

Write-Host "Reimporting project..."
$import = Invoke-Godot @("--headless", "--path", $root, "--import")
$importErrors = $import.Lines | Where-Object { $_ -match $scriptErrorPattern -or $_ -match "^\s+at: " }
if ($importErrors) {
	Write-Host "Import reported script errors:" -ForegroundColor Yellow
	$importErrors | ForEach-Object { Write-Host "  $_" }
}

$suites = Get-ChildItem (Join-Path $root "tests") -Filter "test_*.gd" |
	Where-Object { $_.BaseName -like "*$Filter*" } |
	Sort-Object Name
if (-not $suites) {
	Write-Host "No test suites match '$Filter'." -ForegroundColor Red
	exit 2
}

$failed = @()
foreach ($suite in $suites) {
	Write-Host "--- $($suite.BaseName)"
	$run = Invoke-Godot @("--headless", "--path", $root, "--script", "res://tests/$($suite.Name)")
	$run.Lines |
		Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^Godot Engine v" } |
		ForEach-Object { Write-Host "  $_" }
	# A parse error can still exit 0, so check the output too.
	if ($run.Code -ne 0 -or ($run.Lines -match $scriptErrorPattern) -or ($run.Lines -match "^FAIL:")) {
		$failed += $suite.BaseName
	}
}

Write-Host ""
if ($failed.Count -gt 0) {
	Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
	exit 1
}
Write-Host "All $($suites.Count) test suites passed." -ForegroundColor Green
exit 0
