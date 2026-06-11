# PowerShell script for Windows - Test canary deployment

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('good', 'bad', 'rollback', 'status', 'analysis', 'traffic', 'all')]
    [string]$Action = 'menu'
)

$ErrorActionPreference = "Stop"

# Config
$NAMESPACE = "demo"
$ROLLOUT_NAME = "api"
$API_FILE = "k8s-api\api.yaml"

# Colors
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

# Check prerequisites
function Test-Prerequisites {
    Write-Info "📋 Checking prerequisites..."
    
    # Check kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "❌ kubectl not found"
        exit 1
    }
    
    # Check argo rollouts plugin
    try {
        kubectl argo rollouts version | Out-Null
    } catch {
        Write-Error "❌ kubectl argo rollouts plugin not installed"
        Write-Host "Install: https://argoproj.github.io/argo-rollouts/installation/#kubectl-plugin-installation"
        exit 1
    }
    
    # Check namespace
    try {
        kubectl get namespace $NAMESPACE | Out-Null
    } catch {
        Write-Error "❌ Namespace $NAMESPACE not found"
        exit 1
    }
    
    Write-Success "✓ Prerequisites OK"
    Write-Host ""
}

# Show current status
function Show-CurrentStatus {
    Write-Info "📊 Current Rollout Status:"
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE
    Write-Host ""
}

# Generate traffic
function Start-TrafficGenerator {
    Write-Info "🌐 Generating traffic to API..."
    Write-Host "   (Cần để có metrics cho AnalysisTemplate)"
    
    # Get API service URL
    $API_IP = kubectl get svc $ROLLOUT_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}'
    $API_URL = "http://${API_IP}:8080/"
    
    Write-Host "   Target: $API_URL"
    Write-Host "   Duration: 5 minutes (background process)"
    
    # Create traffic generator script
    $trafficScript = {
        param($url)
        for ($i = 0; $i -lt 300; $i++) {
            try {
                Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 1 | Out-Null
            } catch {}
            Start-Sleep -Seconds 1
        }
    }
    
    # Start background job
    $job = Start-Job -ScriptBlock $trafficScript -ArgumentList $API_URL
    Write-Host "   Traffic generator Job ID: $($job.Id)"
    Write-Host ""
    
    return $job
}

# Test good version
function Test-GoodVersion {
    Write-Host ""
    Write-Success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Success "TEST 1: Deploy GOOD Version (Auto-Promote)"
    Write-Success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    
    Write-Info "📝 Preparing good version (ERROR_RATE=0)..."
    
    # Backup
    Copy-Item $API_FILE "${API_FILE}.backup" -Force
    
    # Update file
    $content = Get-Content $API_FILE -Raw
    $content = $content -replace 'value: ".*" # ERROR_RATE', 'value: "0" # ERROR_RATE'
    $content = $content -replace 'value: "v.*"  # VERSION', 'value: "v1-good"  # VERSION'
    $content = $content -replace 'image: w9-api:.*', 'image: w9-api:good'
    Set-Content $API_FILE $content
    
    Write-Success "✓ Updated $API_FILE:"
    Write-Host "  - ERROR_RATE: 0 (no errors)"
    Write-Host "  - VERSION: v1-good"
    Write-Host "  - IMAGE: w9-api:good"
    Write-Host ""
    
    Read-Host "Press Enter to commit and push"
    
    # Git operations
    git add $API_FILE
    git commit -m "test: deploy good version (expect auto-promote)"
    git push
    
    Write-Host ""
    Write-Info "⏳ Waiting for ArgoCD to sync (30s)..."
    Start-Sleep -Seconds 30
    
    Write-Host ""
    Write-Info "👀 Watching rollout (Ctrl+C to stop)..."
    Write-Host "   Expected: Auto-promote to 100%"
    Write-Host ""
    
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE --watch
}

# Test bad version
function Test-BadVersion {
    Write-Host ""
    Write-Error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Error "TEST 2: Deploy BAD Version (Auto-Abort)"
    Write-Error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    
    Write-Info "📝 Preparing bad version (ERROR_RATE=0.5)..."
    
    # Update file
    $content = Get-Content $API_FILE -Raw
    $content = $content -replace 'value: ".*" # ERROR_RATE', 'value: "0.5" # ERROR_RATE'
    $content = $content -replace 'value: "v.*"  # VERSION', 'value: "v2-bad"  # VERSION'
    $content = $content -replace 'image: w9-api:.*', 'image: w9-api:bad'
    Set-Content $API_FILE $content
    
    Write-Success "✓ Updated $API_FILE:"
    Write-Host "  - ERROR_RATE: 0.5 (50% errors)"
    Write-Host "  - VERSION: v2-bad"
    Write-Host "  - IMAGE: w9-api:bad"
    Write-Host ""
    
    Read-Host "Press Enter to commit and push"
    
    # Git operations
    git add $API_FILE
    git commit -m "test: deploy bad version (expect auto-abort)"
    git push
    
    Write-Host ""
    Write-Info "⏳ Waiting for ArgoCD to sync (30s)..."
    Start-Sleep -Seconds 30
    
    Write-Host ""
    Write-Info "👀 Watching rollout (Ctrl+C to stop)..."
    Write-Host "   Expected: Auto-abort and rollback"
    Write-Host ""
    
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE --watch
}

# Test git rollback
function Test-GitRollback {
    Write-Host ""
    Write-Warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Warning "TEST 3: Git Revert Rollback (<5 minutes)"
    Write-Warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    
    Write-Info "📊 Current git log:"
    git log --oneline -5
    Write-Host ""
    
    Write-Info "⏰ Starting timer..."
    $startTime = Get-Date
    
    Read-Host "Press Enter to revert last commit"
    
    # Git revert
    git revert HEAD --no-edit
    git push
    
    Write-Host ""
    Write-Info "⏳ Waiting for ArgoCD to sync and rollout to complete..."
    
    # Wait for sync
    Start-Sleep -Seconds 30
    
    # Wait for rollout to be healthy
    kubectl argo rollouts status $ROLLOUT_NAME -n $NAMESPACE
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Host ""
    Write-Success "✓ Rollback completed!"
    Write-Host "⏱️  Total time: $duration seconds (< 5 minutes = 300s)"
    
    if ($duration -lt 300) {
        Write-Success "✓ PASS: Rollback time < 5 minutes"
    } else {
        Write-Error "✗ FAIL: Rollback time >= 5 minutes"
    }
    
    Write-Host ""
    Show-CurrentStatus
}

# Show analysis runs
function Show-AnalysisRuns {
    Write-Info "🔍 Recent AnalysisRuns:"
    kubectl get analysisrun -n $NAMESPACE -l rollout=$ROLLOUT_NAME --sort-by=.metadata.creationTimestamp
    Write-Host ""
    
    Write-Info "📊 Latest AnalysisRun details:"
    $latestAR = kubectl get analysisrun -n $NAMESPACE -l rollout=$ROLLOUT_NAME --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}'
    
    if ($latestAR) {
        kubectl describe analysisrun $latestAR -n $NAMESPACE | Select-String -Pattern "Status:" -Context 0,20
    } else {
        Write-Host "No AnalysisRuns found yet"
    }
    Write-Host ""
}

# Show menu
function Show-Menu {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "          CANARY TEST MENU" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "1. Test Good Version (Auto-Promote)"
    Write-Host "2. Test Bad Version (Auto-Abort)"
    Write-Host "3. Test Git Rollback (<5min)"
    Write-Host "4. Show Current Status"
    Write-Host "5. Show AnalysisRuns"
    Write-Host "6. Generate Traffic"
    Write-Host "7. Run All Tests (Full Demo)"
    Write-Host "0. Exit"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
}

# Run all tests
function Start-AllTests {
    Write-Info "🎬 Running full demo sequence..."
    Write-Host ""
    
    $job = Start-TrafficGenerator
    Start-Sleep -Seconds 5
    
    Test-GoodVersion
    
    Write-Host ""
    Read-Host "Test 1 completed. Press Enter to continue to Test 2"
    
    Test-BadVersion
    
    Write-Host ""
    Read-Host "Test 2 completed. Press Enter to continue to Test 3"
    
    Test-GitRollback
    
    Write-Host ""
    Write-Success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Success "  ALL TESTS COMPLETED!"
    Write-Success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    Show-AnalysisRuns
    
    # Stop traffic generator
    if ($job) {
        Stop-Job -Job $job
        Remove-Job -Job $job
    }
}

# Main
function Main {
    Test-Prerequisites
    
    # Handle command line arguments
    switch ($Action) {
        'good' { Test-GoodVersion; return }
        'bad' { Test-BadVersion; return }
        'rollback' { Test-GitRollback; return }
        'status' { Show-CurrentStatus; return }
        'analysis' { Show-AnalysisRuns; return }
        'traffic' { Start-TrafficGenerator; return }
        'all' { Start-AllTests; return }
    }
    
    # Interactive menu
    while ($true) {
        Show-Menu
        $choice = Read-Host "Select option"
        
        switch ($choice) {
            '1' { Test-GoodVersion }
            '2' { Test-BadVersion }
            '3' { Test-GitRollback }
            '4' { Show-CurrentStatus }
            '5' { Show-AnalysisRuns }
            '6' { Start-TrafficGenerator }
            '7' { Start-AllTests }
            '0' { 
                Write-Host "👋 Bye!"
                exit 0
            }
            default {
                Write-Error "Invalid option"
            }
        }
    }
}

# Run
Main
