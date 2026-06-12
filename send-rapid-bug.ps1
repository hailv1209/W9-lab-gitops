# Rapid error traffic generator - gui nhieu request nhat co the
#目标: fire APIHighErrorRate alert (>5% error rate)

$ErrorActionPreference = "SilentlyContinue"
$start = Get-Date
$count = 0
$errors = 0
$success = 0

Write-Host "[RapidBugTraffic] Bat dau gui traffic loi..." -ForegroundColor Red

# Loop nhanh nhat co the
while ($true) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9999/api/bug" -Method GET -TimeoutSec 1 -UseBasicParsing
        $errors++
        $count++
    } catch {
        $errors++
        $count++
    }
    
    if ($count % 100 -eq 0) {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        $perSec = if ($elapsed -gt 0) { [math]::Round($count / $elapsed, 1) } else { 0 }
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent: $count | Errors: $errors ($perSec req/s)" -ForegroundColor Red
    }
}
