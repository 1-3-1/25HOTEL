# ===============================
# ⚡ Step-by-step Debug Script + Everything keyword loop + Top 10 copy
# ===============================

Write-Host "=== [STEP 1] Script directory check ==="
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "baseDir: $baseDir"

# ===============================
Write-Host "=== [STEP 2] USB drive detection ==="
$usb = Get-PSDrive |
    Where-Object { $_.Provider.Name -eq 'FileSystem' -and $_.Name -ne 'C' } |
    Sort-Object Name |
    Select-Object -Last 1

if ($usb) {
    $outputRoot = "$($usb.Name):\"
    Write-Host "USB detected → $outputRoot"
} else {
    $outputRoot = $baseDir
    Write-Host "No USB detected → Using baseDir: $outputRoot"
}

# ===============================
Write-Host "=== [STEP 3] Build output folder & file path ==="
$date = Get-Date -Format "yyyyMMdd_HHmmss"
$hostname = $env:COMPUTERNAME
$folderName = "${hostname}_${date}"
$outputFolder = Join-Path -Path $outputRoot -ChildPath $folderName

# 폴더 생성
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

# 로그 파일 경로
$fileName = "${hostname}_${date}.txt"
$outputFile = Join-Path -Path $outputFolder -ChildPath $fileName
Write-Host "outputFile: $outputFile"

# ===============================
Write-Host "=== [STEP 4] Out-File test ==="
"RESULT" | Out-File -LiteralPath $outputFile -Encoding UTF8
Write-Host "File write test completed."

# ===============================
Write-Host "=== [STEP 5] Locate es.exe ==="
$esPath = Join-Path $baseDir "es.exe"
if (-not (Test-Path -LiteralPath $esPath)) {
    $cmd = Get-Command es.exe -ErrorAction SilentlyContinue
    if ($cmd) { $esPath = $cmd.Path }
}
if (Test-Path -LiteralPath $esPath) {
    Write-Host "es.exe found at: $esPath"
} else {
    Write-Host "ERROR: es.exe not found."
    "ERROR: es.exe not found." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Pause
    exit 1
}

# ===============================
Write-Host "=== [STEP 6] Keyword search loop (direct call) ==="

# keyword file path
$keywordFile = Join-Path $baseDir "keywords.txt"

if (-not (Test-Path -LiteralPath $keywordFile)) {
    Write-Host "❌ keywords.txt not found in: $baseDir"
    "ERROR: keywords.txt not found." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Pause
    exit 1
}

# ✅ UTF-8로 키워드 읽기
$keywords = Get-Content -Path $keywordFile -Encoding UTF8

Write-Host "Loaded keywords:"
foreach ($kw in $keywords) { Write-Host " - $kw" }

foreach ($keyword in $keywords) {
    Write-Host "----------------------------------------"
    Write-Host "🔍 Keyword raw: [$keyword]"
    Write-Host "   Type: $($keyword.GetType().FullName)"
    "=== Keyword: $keyword ===" | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append

    # ✅ 인자 배열 방식으로 안전하게 전달
    $argList = @($keyword)
    Write-Host "⚡ Running:" $esPath $argList

    $esOutput = & $esPath @argList 2>&1
    $esExit = $LASTEXITCODE

    Write-Host "   Exit code: $esExit"
    if ($esOutput) {
        Write-Host "=== Result ==="
        $esOutput | ForEach-Object { Write-Host "   $_" }
        $esOutput | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    } else {
        Write-Host "   No result."
        "No result." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    }

    "" | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Write-Host "----------------------------------------"
}

Write-Host "=== Keyword search completed. Log saved to: $outputFile ==="

# ===============================
Write-Host "=== [STEP 7] Copy newest files up to 100MB total (skip >50MB & .lnk) ==="

try {
    # 🔸 로그에서 파일 경로 추출
    $allPaths = Get-Content -Path $outputFile -Encoding UTF8 |
        Where-Object { ($_ -match '^[A-Za-z]:\\') -and (Test-Path $_) }

    if ($allPaths.Count -eq 0) {
        Write-Host "No valid file paths found in search result."
    }
    else {
        # 🔸 최신순으로 정렬 + 파일 크기 정보 수집
        $sortedFiles = $allPaths |
            ForEach-Object {
                $item = Get-Item $_
                [PSCustomObject]@{
                    Path = $_
                    LastWriteTime = $item.LastWriteTime
                    Length = $item.Length
                    Extension = [System.IO.Path]::GetExtension($_)
                }
            } |
            Sort-Object LastWriteTime -Descending

        # 🔸 용량 제한
        $maxTotalBytes = 100MB
        $maxFileBytes = 50MB
        $selectedFiles = @()
        $totalBytes = 0

        foreach ($file in $sortedFiles) {
            # .lnk 파일은 아예 건너뜀
            if ($file.Extension -eq ".lnk") {
                Write-Host ("⚠️ Skipping (.lnk): {0}" -f $file.Path)
                continue
            }

            # 50MB 넘는 파일도 건너뜀
            if ($file.Length -gt $maxFileBytes) {
                Write-Host ("⚠️ Skipping (>{0}MB): {1}" -f ($maxFileBytes / 1MB), $file.Path)
                continue
            }

            # 총합 100MB 넘지 않는 경우만 선택
            if (($totalBytes + $file.Length) -le $maxTotalBytes) {
                $selectedFiles += $file
                $totalBytes += $file.Length
            } else {
                break
            }
        }

        if ($selectedFiles.Count -eq 0) {
            Write-Host "No files selected within 100MB total and 50MB per-file limits."
        }
        else {
            # TOP_COPY 폴더 생성
            $copyFolder = Join-Path $outputFolder "TOP_COPY_100MB"
            New-Item -ItemType Directory -Path $copyFolder -Force | Out-Null

            Write-Host "Copying files up to 100MB total → $copyFolder"
            Write-Host ("Selected total size: {0:N2} MB" -f ($totalBytes / 1MB))

            foreach ($file in $selectedFiles) {
                $dest = Join-Path $copyFolder (Split-Path $file.Path -Leaf)
                Write-Host ("📎 {0} ({1:N2} MB)" -f $file.Path, ($file.Length / 1MB))
                Copy-Item -Path $file.Path -Destination $dest -Force -ErrorAction SilentlyContinue
            }

            Write-Host "✅ Files copied to: $copyFolder"
        }
    }
}
catch {
    Write-Host "❌ Error during file copy: $_"
}