Write-Host "=== [STEP 6] Keyword search loop (direct call) ==="

# 현재 디렉터리 기준
$baseDir = Get-Location
$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')

# data_날짜시간 폴더 생성
$dataFolder = Join-Path $baseDir ("data_$timestamp")
New-Item -ItemType Directory -Path $dataFolder -Force | Out-Null

# 로그 파일 경로
$outputFile = Join-Path $dataFolder "result_$timestamp.log"

Write-Host "[DBG] BaseDir: $baseDir"
Write-Host "[DBG] DataFolder: $dataFolder"
Write-Host "[DBG] OutputFile: $outputFile"

# keyword file path (현재 폴더)
$keywordFile = Join-Path $baseDir "keywords.txt"
Write-Host "[DBG] KeywordFile: $keywordFile"

if (-not (Test-Path -LiteralPath $keywordFile)) {
    Write-Host "❌ keywords.txt not found in: $baseDir"
    "ERROR: keywords.txt not found." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Pause
    exit 1
}

# ✅ UTF-8로 키워드 읽기
$keywords = Get-Content -Path $keywordFile -Encoding UTF8
Write-Host "[DBG] Loaded $(($keywords | Measure-Object).Count) keywords"

Write-Host "Loaded keywords:"
foreach ($kw in $keywords) { Write-Host " - $kw" }

# es.exe 경로 (현재 폴더 기준)
$esPath = Join-Path $baseDir "es.exe"
Write-Host "[DBG] esPath: $esPath"
if (-not (Test-Path $esPath)) {
    Write-Host "❌ es.exe not found in: $baseDir"
    "ERROR: es.exe not found." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Pause
    exit 1
}

foreach ($keyword in $keywords) {
    Write-Host "----------------------------------------"
    Write-Host "🔍 Keyword raw: [$keyword]"
    Write-Host "   Type: $($keyword.GetType().FullName)"
    "=== Keyword: $keyword ===" | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append

    # 인자 배열 방식으로 안전하게 전달
    $argList = @($keyword)
    Write-Host "[DBG] argList: $argList"

    Write-Host "⚡ Running:" $esPath $argList

    try {
        $esOutput = & $esPath @argList 2>&1
        $esExit = $LASTEXITCODE

        Write-Host "[DBG] esExit: $esExit"

        Write-Host "   Exit code: $esExit"
        if ($esOutput) {
            Write-Host "=== Result ==="
            $esOutput | ForEach-Object { Write-Host "   $_" }
            $esOutput | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
        } else {
            Write-Host "   No result."
            "No result." | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
        }
    }
    catch {
        Write-Host "❌ Error while running es.exe: $_"
        "Error: $_" | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    }

    "" | Out-File -LiteralPath $outputFile -Encoding UTF8 -Append
    Write-Host "----------------------------------------"
}

Write-Host "=== Keyword search completed. Log saved to: $outputFile ==="

# ===============================
Write-Host "=== [STEP 7] Copy newest files up to 100MB total (skip >50MB & .lnk) ==="

try {
    # 로그에서 파일 경로 추출
    Write-Host "[DBG] Reading log file: $outputFile"
    $allPaths = Get-Content -Path $outputFile -Encoding UTF8 |
        Where-Object { ($_ -match '^[A-Za-z]:\\') -and (Test-Path $_) }
    Write-Host "[DBG] Found $($allPaths.Count) valid file paths"

    if ($allPaths.Count -eq 0) {
        Write-Host "No valid file paths found in search result."
    }
    else {
        # 최신순으로 정렬 + 파일 크기 정보 수집
        $sortedFiles = $allPaths |
            ForEach-Object {
                try {
                    $item = Get-Item $_
                    [PSCustomObject]@{
                        Path = $_
                        LastWriteTime = $item.LastWriteTime
                        Length = $item.Length
                        Extension = [System.IO.Path]::GetExtension($_)
                    }
                } catch {
                    Write-Host "[DBG] Skipping invalid path: $_"
                }
            } |
            Sort-Object LastWriteTime -Descending

        Write-Host "[DBG] SortedFiles Count: $($sortedFiles.Count)"

        # 용량 제한
        $maxTotalBytes = 100MB
        $maxFileBytes = 50MB
        $selectedFiles = @()
        $totalBytes = 0

        foreach ($file in $sortedFiles) {
            if ($null -eq $file) { continue }
            Write-Host "[DBG] Evaluating file: $($file.Path) ($($file.Length/1MB) MB)"

            # .lnk 파일은 아예 건너뜀
            if ($file.Extension -eq ".lnk") {
                Write-Host ("⚠️ Skipping (.lnk): {0}" -f $file.Path)
                continue
            }

            # 50MB 넘는 파일도 건너뜀
            if ($file.Length -gt $maxFileBytes) {
                Write-Host ("⚠️ Skipping (> {0}MB): {1}" -f ($maxFileBytes / 1MB), $file.Path)
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

        Write-Host "[DBG] SelectedFiles Count: $($selectedFiles.Count)"
        Write-Host ("[DBG] Total selected size: {0:N2} MB" -f ($totalBytes / 1MB))

        if ($selectedFiles.Count -eq 0) {
            Write-Host "No files selected within 100MB total and 50MB per-file limits."
        }
        else {
            # data_폴더 안에 TOP_COPY 폴더 생성
            $copyFolder = Join-Path $dataFolder "TOP_COPY_100MB"
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


# ===============================
Write-Host "=== [STEP 9] Cleanup: Stop Everything and Remove temp_* folders on Desktop ==="

try {
    # 1️⃣ Everything 프로세스 종료
    $processes = Get-Process -Name "Everything" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "🛑 Stopping Everything.exe process..."
        $processes | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                Write-Host ("   Killed PID {0}" -f $_.Id)
            } catch {
                Write-Host "   ⚠️ Could not stop PID $($_.Id): $_"
            }
        }
        Start-Sleep -Seconds 1
        Write-Host "✅ Everything process terminated."
    } else {
        Write-Host "No Everything.exe process found."
    }

    # 2️⃣ temp_* 폴더 삭제
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
    $tempFolders = Get-ChildItem -Path $desktopPath -Directory -Filter "tempsumin_*" -ErrorAction SilentlyContinue

    if ($tempFolders.Count -eq 0) {
        Write-Host "No temp_* folders found on Desktop."
    } else {
        foreach ($folder in $tempFolders) {
            Write-Host ("🧹 Removing folder: {0}" -f $folder.FullName)
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "✅ Cleanup complete. All temp_* folders removed."
    }
}
catch {
    Write-Host "❌ Error during cleanup: $_"
}
