Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Resolve-Path "$PSScriptRoot\.."
$outDir = "$repoRoot\build\out"
$zipPath = "$outDir\StealthTracker.zip"
$extPath = "C:\Users\justi\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\StealthTracker.ext"

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)

$filesToInclude = @(
    "extension.xml",
    "scripts\stealthtracker.lua",
    "graphics\icons\stealth_icon.png"
)

foreach ($relPath in $filesToInclude) {
    $fullPath = Join-Path $repoRoot $relPath
    if (Test-Path $fullPath) {
        $entryName = $relPath.Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $fullPath, $entryName)
        Write-Host "Added: $entryName"
    } else {
        Write-Warning "File not found: $fullPath"
    }
}

$zip.Dispose()

Copy-Item $zipPath -Destination $extPath -Force
Write-Host "Successfully packaged and copied to: $extPath"

# Verify zip entry paths
$readZip = [System.IO.Compression.ZipFile]::OpenRead($extPath)
Write-Host "`nContents of deployed ${extPath}:"
foreach ($entry in $readZip.Entries) {
    Write-Host "  $($entry.FullName) ($($entry.Length) bytes)"
}
$readZip.Dispose()
