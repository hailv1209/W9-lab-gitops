# Script gửi traffic đến API để tạo metrics cho AnalysisTemplate
# Chạy: .\send-traffic.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "🚀 GỬI TRAFFIC ĐẾN API" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Lấy IP của API service
$api_ip = kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'

if (-not $api_ip) {
    Write-Host "❌ Không tìm thấy service API" -ForegroundColor Red
    exit 1
}

Write-Host "📍 API Service: http://${api_ip}:8080" -ForegroundColor Green
Write-Host "⏰ Gửi traffic liên tục... Nhấn Ctrl+C để dừng" -ForegroundColor Yellow
Write-Host ""

$count = 0
$success = 0
$failed = 0

try {
    while ($true) {
        try {
            $response = Invoke-RestMethod -Uri "http://${api_ip}:8080/api/data" -Method GET -TimeoutSec 2
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
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "📊 TỔNG KẾT" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Total requests: $count"
    Write-Host "Success: $success"
    Write-Host "Failed: $failed"
    if ($count -gt 0) {
        $finalRate = [math]::Round(($success / $count) * 100, 1)
        Write-Host "Success rate: ${finalRate}%"
    }
}
