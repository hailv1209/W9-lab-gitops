param([string]$TargetUrl = "http://localhost:8888/api/bug", [int]$Workers = 4)
$ErrorActionPreference = "SilentlyContinue"
$start = Get-Date
$count = 0
$errors = 0

function SendBugRequest {
    param($url, $workerId)
    $localCount = 0
    $wc = New-Object System.Net.WebClient
    while ($true) {
        try {
            $wc.DownloadString($url) | Out-Null
        } catch {}
        $localCount++
        if ($localCount % 200 -eq 0) {
            Write-Host "[Worker $workerId] Sent: $localCount" -ForegroundColor DarkRed
        }
    }
}

$jobs = @()
for ($i = 1; $i -le $Workers; $i++) {
    $j = Start-Job -ScriptBlock $function:SendBugRequest -ArgumentList $TargetUrl, $i
    $jobs += $j
    Write-Host "[+] Worker $i started (JobId=$($j.Id))" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Dang gui traffic loi toi $TargetUrl" -ForegroundColor Yellow
Write-Host "Nhan Ctrl+C de dung" -ForegroundColor Gray
Write-Host ""

try {
    while ($true) {
        Start-Sleep 10
        $total = ($jobs | Receive-Job -Keep | Measure-Object).Count * 200
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Da gui ~$total requests loi" -ForegroundColor Red
    }
} finally {
    Write-Host "Dang dung..." -ForegroundColor Yellow
    $jobs | Stop-Job -ErrorAction SilentlyContinue
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
}
