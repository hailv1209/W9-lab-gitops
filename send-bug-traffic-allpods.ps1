# Script gui traffic loi 100% den TAT CA cac pod API
# De nhanh chong day error rate len > 5%

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[START] GUI TRAFFIC LOI DEN TAT CA PODS" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$pods = @("10.244.0.141:8080", "10.244.0.145:8080", "10.244.0.146:8080", "10.244.0.147:8080")
Write-Host "Targets:" -ForegroundColor Gray
$pods | ForEach-Object { Write-Host "  -> http://$_/api/bug" -ForegroundColor Gray }

$count = 0
$start = Get-Date

# Bat dau port-forward de test
Write-Host ""
Write-Host "[INFO] Bat dau gui traffic..." -ForegroundColor Yellow

$jobs = @()
foreach ($pod in $pods) {
    $job = Start-Job -ScriptBlock {
        param($pod, $scriptRoot)
        $count = 0
        while ($true) {
            try {
                $r = Invoke-WebRequest -Uri "http://$pod/api/bug" -Method GET -TimeoutSec 1 -UseBasicParsing -ErrorAction SilentlyContinue
            } catch {}
            $count++
            if ($count % 50 -eq 0) {
                Write-Host "[$pod] Sent: $count" -ForegroundColor Red
            }
            Start-Sleep -Milliseconds 100
        }
    } -ArgumentList $pod, $PSScriptRoot
    $jobs += $job
}

Write-Host "[INFO] $jobs.Count workers dang chay..." -ForegroundColor Cyan
Write-Host "[INFO] Stop: Stop-Job on these jobs" -ForegroundColor Gray
Write-Host ""

# Hien thi tong hop moi 10s
while ($true) {
    Start-Sleep 10
    $total = 0
    foreach ($j in $jobs) {
        $data = Receive-Job -Job $j 2>$null
        $total += $data.Count
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total errors sent: $total" -ForegroundColor Red
}
