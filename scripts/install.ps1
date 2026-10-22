# ==============================================================================
# MF Lab - Tek Tıkla Öğrenci Kurulum Betiği
# Kullanım (PowerShell):
#   irm https://raw.githubusercontent.com/mustafafenerci/mflab/main/scripts/install.ps1 | iex
# ==============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   🎓 MF Lab - Öğrenci Ders Ortamı Kurucusu (Windows)   " -ForegroundColor Cyan
Write-Host "   Geliştirici & Eğitmen: Mustafa Fenerci                 " -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$repo = "mustafafenerci/mflab"
# Kurulum dosyasının adında sürüm var (MFLab-Setup-vX.Y.Z.exe); en güncelini GitHub'dan bul.
$assetName = "MFLab-Setup.exe"
$downloadUrl = "https://github.com/$repo/releases/latest/download/$assetName"
$checksumUrl = $null
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "MFLab-Installer" }
    $asset = $release.assets | Where-Object { $_.name -like "MFLab-Setup-v*.exe" } | Select-Object -First 1
    if ($asset) {
        $assetName = $asset.name
        $downloadUrl = $asset.browser_download_url
        $sumAsset = $release.assets | Where-Object { $_.name -eq "$($asset.name).sha256" } | Select-Object -First 1
        if ($sumAsset) { $checksumUrl = $sumAsset.browser_download_url }
    }
} catch { }
$tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $assetName)

Write-Host "⏳ En güncel MF Lab kurulum dosyası indiriliyor..." -ForegroundColor Yellow
Write-Host "   Kaynak: $downloadUrl" -ForegroundColor Gray

try {
    # WebClient veya Invoke-WebRequest ile indir
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($downloadUrl, $tempFile)
    Write-Host "✔ İndirme tamamlandı: $tempFile" -ForegroundColor Green
} catch {
    Write-Host "✖ İndirme sırasında bir hata oluştu: $_" -ForegroundColor Red
    Write-Host "Lütfen tarayıcınızdan şu adrese giderek manuel indirin: https://github.com/$repo/releases/latest" -ForegroundColor Yellow
    exit 1
}

# İndirilen dosyanın GitHub'daki SHA-256 özetiyle aynı olduğunu doğrula.
if ($checksumUrl) {
    try {
        $expected = ([regex]::Match((Invoke-RestMethod -Uri $checksumUrl), '[a-fA-F0-9]{64}')).Value.ToLower()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($tempFile)
        $actual = ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLower()
        $fs.Close()
        if ($expected -and $actual -ne $expected) {
            Remove-Item -Force $tempFile -ErrorAction SilentlyContinue
            Write-Host "✖ Dosya doğrulanamadı (SHA-256 uyuşmuyor). Kurulum durduruldu." -ForegroundColor Red
            exit 1
        }
        Write-Host "✔ SHA-256 doğrulandı." -ForegroundColor Green
    } catch {
        Write-Host "⚠ SHA-256 doğrulaması yapılamadı: $_" -ForegroundColor Yellow
    }
}

Write-Host "🚀 Kurulum sihirbazı başlatılıyor..." -ForegroundColor Cyan
try {
    Start-Process -FilePath $tempFile -Wait
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "✔ MF Lab kurulumu başarıyla tamamlandı!" -ForegroundColor Green
    Write-Host "Masaüstünüzdeki 'MF Lab' simgesine çift tıklayarak dersinizi seçebilirsiniz." -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Kurulum başlatılamadı: $_" -ForegroundColor Red
}
