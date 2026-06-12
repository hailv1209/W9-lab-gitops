# Script gui traffic den API de tao metrics cho AnalysisTemplate
# Chay: .\send-traffic.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[START] GUI TRAFFIC DEN API" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Start port-forwarding
Write-Host "[INFO] Starting port-forward to API service..." -ForegroundColor Gray
$pfJob = Start-Process kubectl -ArgumentList "port-forward svc/api -n demo 8888:8080" -NoNewWindow -PassThru
Start-Sleep -Seconds 3

Write-Host "[INFO] API Service: http://localhost:8888" -ForegroundColor Green
Write-Host "[WAIT] Gui traffic lien tuc... Nhan Ctrl+C de dung" -ForegroundColor Yellow
Write-Host ""

$count = 0
$success = 0
$failed = 0

try {
    while ($true) {
        try {
            # Fix route: using "/" instead of "/api/data" since app.py only serves "/"
            $response = Invoke-RestMethod -Uri "http://localhost:8888/" -Method GET -TimeoutSec 2
            $count++
            $success++
            
            if ($count % 10 -eq 0) {
                $successRate = [math]::Round(($success / $count) * 100, 1)
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent: $count | Success: $success | Failed: $failed | Rate: ${successRate}%" -ForegroundColor Gray
            }
        } catch {
            $count++
            $failed++
            
            if ($count % 10 -eq 0) {
                $successRate = [math]::Round(($success / $count) * 100, 1)
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent: $count | Success: $success | Failed: $failed | Rate: ${successRate}%" -ForegroundColor Yellow
            }
        }
        
        Start-Sleep -Milliseconds 500
    }
} finally {
    if ($pfJob) { 
        Write-Host "`n[INFO] Stopping port-forward..." -ForegroundColor Gray
        Stop-Process -Id $pfJob.Id -Force -ErrorAction SilentlyContinue 
    }
    
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "[SUMMARY] TONG KET" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Total requests: $count"
    Write-Host "Success: $success"
    Write-Host "Failed: $failed"
    if ($count -gt 0) {
        $finalRate = [math]::Round(($success / $count) * 100, 1)
        Write-Host "Success rate: ${finalRate}%"
    }
}
