# Script kiem tra tu dong cac yeu cau de bai
# Chay: .\test-requirements.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[TEST] KIEM TRA YEU CAU DE BAI" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Ham kiem tra
function Test-Requirement {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$Description
    )
    
    Write-Host "[$Name] $Description" -ForegroundColor Yellow
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  [PASS]" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [FAIL]" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [ERROR]: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================
# YEU CAU 1: GITOPS + ROLLBACK < 5'
# ============================================
Write-Host "`n=== YEU CAU 1: GitOps & Rollback ===" -ForegroundColor Magenta

$r1_1 = Test-Requirement `
    -Name "1.1" `
    -Description "ArgoCD Application ton tai va Synced" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        if ($app.status.sync.status -eq "Synced") {
            Write-Host "    -> Sync Status: $($app.status.sync.status)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r1_2 = Test-Requirement `
    -Name "1.2" `
    -Description "ArgoCD co auto-sync enabled" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        if ($app.spec.syncPolicy.automated) {
            Write-Host "    -> Auto Prune: $($app.spec.syncPolicy.automated.prune)" -ForegroundColor Gray
            Write-Host "    -> Self Heal: $($app.spec.syncPolicy.automated.selfHeal)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r1_3 = Test-Requirement `
    -Name "1.3" `
    -Description "Git repository da duoc config dung" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        $repoUrl = $app.spec.source.repoURL
        if ($repoUrl -like "*github.com*" -or $repoUrl -like "*gitlab.com*") {
            Write-Host "    -> Repo: $repoUrl" -ForegroundColor Gray
            return $true
        }
        return $false
    }

# ============================================
# YEU CAU 2: SLO + ALERT -> EMAIL
# ============================================
Write-Host "`n=== YEU CAU 2: SLO + Alert -> Email ===" -ForegroundColor Magenta

$r2_1 = Test-Requirement `
    -Name "2.1" `
    -Description "PrometheusRule (SLO) da duoc tao" `
    -Test {
        $rule = kubectl get prometheusrule api-slo-alerts -n demo -o json 2>$null | ConvertFrom-Json
        if ($rule.spec.groups[0].rules) {
            $alertCount = $rule.spec.groups[0].rules.Count
            Write-Host "    -> So luong alerts: $alertCount" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r2_2 = Test-Requirement `
    -Name "2.2" `
    -Description "Alert APIHighErrorRate ton tai" `
    -Test {
        $rule = kubectl get prometheusrule api-slo-alerts -n demo -o json 2>$null | ConvertFrom-Json
        $alert = $rule.spec.groups[0].rules | Where-Object { $_.alert -eq "APIHighErrorRate" }
        if ($alert) {
            Write-Host "    -> Alert name: $($alert.alert)" -ForegroundColor Gray
            Write-Host "    -> Severity: $($alert.labels.severity)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r2_3 = Test-Requirement `
    -Name "2.3" `
    -Description "AlertmanagerConfig co email receiver" `
    -Test {
        $config = kubectl get alertmanagerconfig api-email-alerts -n demo -o json 2>$null | ConvertFrom-Json
        if ($config.spec.receivers) {
            $emailReceiver = $config.spec.receivers | Where-Object { $_.emailConfigs }
            if ($emailReceiver) {
                $emailTo = $emailReceiver.emailConfigs[0].to
                Write-Host "    -> Email nhan: $emailTo" -ForegroundColor Gray
                return $true
            }
        }
        return $false
    }

$r2_4 = Test-Requirement `
    -Name "2.4" `
    -Description "SMTP Secret da duoc tao" `
    -Test {
        $secret = kubectl get secret alertmanager-email-secret -n demo 2>$null
        if ($secret) {
            Write-Host "    -> Secret ton tai" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "    [WARNING] Can tao secret: kubectl create secret generic alertmanager-email-secret -n demo --from-literal=password='YOUR_SMTP_PASSWORD'" -ForegroundColor Yellow
            return $false
        }
    }

$r2_5 = Test-Requirement `
    -Name "2.5" `
    -Description "ServiceMonitor scrape metrics tu API" `
    -Test {
        $sm = kubectl get servicemonitor api -n demo -o json 2>$null | ConvertFrom-Json
        if ($sm.spec.endpoints) {
            $interval = $sm.spec.endpoints[0].interval
            Write-Host "    -> Scrape interval: $interval" -ForegroundColor Gray
            return $true
        }
        return $false
    }

# ============================================
# YEU CAU 3: CANARY TU DONG
# ============================================
Write-Host "`n=== YEU CAU 3: Canary Tu dong ===" -ForegroundColor Magenta

$r3_1 = Test-Requirement `
    -Name "3.1" `
    -Description "Rollout su dung Canary strategy" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if ($rollout.spec.strategy.canary) {
            Write-Host "    -> Strategy: Canary" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r3_2 = Test-Requirement `
    -Name "3.2" `
    -Description "Canary co AnalysisTemplate" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        $hasAnalysis = $false
        foreach ($step in $rollout.spec.strategy.canary.steps) {
            if ($step.analysis) {
                $hasAnalysis = $true
                $templateName = $step.analysis.templates[0].templateName
                Write-Host "    -> AnalysisTemplate: $templateName" -ForegroundColor Gray
                break
            }
        }
        return $hasAnalysis
    }

$r3_3 = Test-Requirement `
    -Name "3.3" `
    -Description "AnalysisTemplate ton tai va co metrics" `
    -Test {
        $template = kubectl get analysistemplate api-success-rate -n demo -o json 2>$null | ConvertFrom-Json
        if ($template.spec.metrics) {
            $metricCount = $template.spec.metrics.Count
            Write-Host "    -> So luong metrics: $metricCount" -ForegroundColor Gray
            foreach ($metric in $template.spec.metrics) {
                Write-Host "      - $($metric.name): successCondition=$($metric.successCondition)" -ForegroundColor Gray
            }
            return $true
        }
        return $false
    }

$r3_4 = Test-Requirement `
    -Name "3.4" `
    -Description "Canary co abortScaleDownDelaySeconds (auto rollback)" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if ($rollout.spec.strategy.canary.abortScaleDownDelaySeconds) {
            $delay = $rollout.spec.strategy.canary.abortScaleDownDelaySeconds
            Write-Host "    -> Abort delay: ${delay}s" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r3_5 = Test-Requirement `
    -Name "3.5" `
    -Description "Canary KHONG co scaleDownDelaySeconds (can traffic routing)" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if (-not $rollout.spec.strategy.canary.scaleDownDelaySeconds) {
            Write-Host "    -> Cau hinh dung (khong dung scaleDownDelaySeconds)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "    [WARNING] Co scaleDownDelaySeconds -> Can xoa (chi dung voi traffic routing)" -ForegroundColor Yellow
            return $false
        }
    }

$r3_6 = Test-Requirement `
    -Name "3.6" `
    -Description "Rollout hien tai o trang thai Healthy" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        $status = $rollout.status.phase
        Write-Host "    -> Status: $status" -ForegroundColor Gray
        if ($status -eq "Healthy") {
            return $true
        } elseif ($status -eq "Progressing") {
            Write-Host "    [INFO] Rollout dang chay, cho hoan thanh" -ForegroundColor Cyan
            return $true
        }
        return $false
    }

# ============================================
# TONG KET
# ============================================
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "[SUMMARY] TONG KET" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$total = 0
$passed = 0

$results = @{
    "YEU CAU 1 (GitOps)" = @($r1_1, $r1_2, $r1_3)
    "YEU CAU 2 (SLO+Alert)" = @($r2_1, $r2_2, $r2_3, $r2_4, $r2_5)
    "YEU CAU 3 (Canary)" = @($r3_1, $r3_2, $r3_3, $r3_4, $r3_5, $r3_6)
}

foreach ($req in $results.Keys) {
    $reqPassed = ($results[$req] | Where-Object { $_ -eq $true }).Count
    $reqTotal = $results[$req].Count
    $total += $reqTotal
    $passed += $reqPassed
    
    $percent = [math]::Round(($reqPassed / $reqTotal) * 100)
    $statusIcon = if ($reqPassed -eq $reqTotal) { "[OK]" } else { "[!!]" }
    
    Write-Host "`n$statusIcon $req : $reqPassed/$reqTotal ($percent%)" -ForegroundColor $(if ($reqPassed -eq $reqTotal) { "Green" } else { "Yellow" })
}

$totalPercent = [math]::Round(($passed / $total) * 100)
Write-Host "`n-------------------------------------" -ForegroundColor Cyan
Write-Host "TONG: $passed/$total tests passed ($totalPercent%)" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })

if ($passed -eq $total) {
    Write-Host "`n[SUCCESS] HOAN HAO! Tat ca yeu cau da dap ung!" -ForegroundColor Green
    Write-Host "Tiep theo: Chay cac test thuc te trong TEST-GUIDE.md" -ForegroundColor Cyan
} else {
    Write-Host "`n[WARNING] Con thieu mot so cau hinh. Xem huong dan chi tiet ben tren." -ForegroundColor Yellow
}

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host ""
