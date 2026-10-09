param(
  [string]$Version = "1.1.2",
  [switch]$SkipFlutter = $false
)

$ErrorActionPreference = "Stop"
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  MF Lab - Derleme & Kurulum Paketi Uretici" -ForegroundColor Yellow
Write-Host "  Surum: $Version" -ForegroundColor Gray
Write-Host "==============================================" -ForegroundColor Cyan

$root = $PSScriptRoot
Set-Location $root

if (-not $SkipFlutter) {
  Write-Host "`n[1/3] Flutter Release derleniyor..." -ForegroundColor Green
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter derlemesi basarisiz oldu."
    exit 1
  }
} else {
  Write-Host "`n[1/3] Flutter derlemesi atlandi (-SkipFlutter)." -ForegroundColor DarkGray
}

Write-Host "`n[2/3] Inno Setup ile kurulum paketi olusturuluyor..." -ForegroundColor Green
$isccCandidates = @(
  "C:\Users\MF-KUN\AppData\Local\Programs\Inno Setup 6\ISCC.exe",
  "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  Write-Error "Inno Setup 6 (ISCC.exe) bulunamadi."
  exit 1
}

& "$iscc" /DMyAppVersion=$Version "installer\mflab.iss"
if ($LASTEXITCODE -ne 0) {
  Write-Error "Inno Setup derlemesi basarisiz oldu."
  exit 1
}

Write-Host "`n[3/3] Kurulum paketi masaustune kopyalaniyor..." -ForegroundColor Green
$desktop = [Environment]::GetFolderPath('Desktop')
$setupDist = Join-Path $root "dist\MFLab-Setup.exe"
# Masaüstündeki kopyanın adına sürüm yazılır; hangisinin yeni olduğu hemen anlaşılır.
$setupDesktop = Join-Path $desktop "MFLab-Setup-v$Version.exe"
Get-ChildItem -Path $desktop -Filter "MFLab-Setup*.exe" -ErrorAction SilentlyContinue |
  Remove-Item -Force -ErrorAction SilentlyContinue

Copy-Item -Path $setupDist -Destination $setupDesktop -Force

Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "  BASARILI! " -ForegroundColor Green
Write-Host "  Masaustune kopyalandi: $setupDesktop" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
