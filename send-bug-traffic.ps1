# Script gui 100% request loi den /api/bug de fire SLO alert
# Chay: .\send-bug-traffic.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[START] GUI TRAFFIC LOI 100% DEN /api/bug" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Target: http://localhost:9999/api/bug" -ForegroundColor Gray
Write-Host "Muc tieu: Fire APIHighErrorRate alert" -ForegroundColor Yellow
Write-Host ""

$count = 0
$errors = 0
$start = Get-Date

try {
    while ($true) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:9999/api/bug" -Method GET -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
            $count++
            $errors++
            $status = if ($response) { $response.StatusCode } else { "Error" }
        } catch {
            $count++
            $errors++
            $status = "Error/Timeout"
        }
        
        if ($count % 20 -eq 0) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            $rate = if ($count -gt 0) { [math]::Round(($errors / $count) * 100, 1) } else { 0 }
            $perSec = if ($elapsed -gt 0) { [math]::Round($count / $elapsed, 1) } else { 0 }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent: $count | Errors: $errors ($rate%) | Speed: ${perSec}req/s" -ForegroundColor Red
        }
        
        Start-Sleep -Milliseconds 200
    }
} finally {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "[STOPPED]" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Total requests: $count"
    Write-Host "Total errors: $errors"
}
