# 🧪 Script kiểm tra tự động các yêu cầu đề bài
# Chạy: .\test-requirements.ps1

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "🧪 KIỂM TRA YÊU CẦU ĐỀ BÀI" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Hàm kiểm tra
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
            Write-Host "  ✅ PASS" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ❌ FAIL" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  ❌ ERROR: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================
# YÊU CẦU 1: GITOPS + ROLLBACK < 5'
# ============================================
Write-Host "`n1️⃣ YÊU CẦU 1: GitOps & Rollback" -ForegroundColor Magenta
Write-Host "─────────────────────────────────" -ForegroundColor Magenta

$r1_1 = Test-Requirement `
    -Name "1.1" `
    -Description "ArgoCD Application tồn tại và Synced" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        if ($app.status.sync.status -eq "Synced") {
            Write-Host "    → Sync Status: $($app.status.sync.status)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r1_2 = Test-Requirement `
    -Name "1.2" `
    -Description "ArgoCD có auto-sync enabled" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        if ($app.spec.syncPolicy.automated) {
            Write-Host "    → Auto Prune: $($app.spec.syncPolicy.automated.prune)" -ForegroundColor Gray
            Write-Host "    → Self Heal: $($app.spec.syncPolicy.automated.selfHeal)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r1_3 = Test-Requirement `
    -Name "1.3" `
    -Description "Git repository đã được config đúng" `
    -Test {
        $app = kubectl get app api -n argocd -o json 2>$null | ConvertFrom-Json
        $repoUrl = $app.spec.source.repoURL
        if ($repoUrl -like "*github.com*" -or $repoUrl -like "*gitlab.com*") {
            Write-Host "    → Repo: $repoUrl" -ForegroundColor Gray
            return $true
        }
        return $false
    }

# ============================================
# YÊU CẦU 2: SLO + ALERT → EMAIL
# ============================================
Write-Host "`n2️⃣ YÊU CẦU 2: SLO + Alert → Email" -ForegroundColor Magenta
Write-Host "─────────────────────────────────" -ForegroundColor Magenta

$r2_1 = Test-Requirement `
    -Name "2.1" `
    -Description "PrometheusRule (SLO) đã được tạo" `
    -Test {
        $rule = kubectl get prometheusrule api-slo-alerts -n demo -o json 2>$null | ConvertFrom-Json
        if ($rule.spec.groups[0].rules) {
            $alertCount = $rule.spec.groups[0].rules.Count
            Write-Host "    → Số lượng alerts: $alertCount" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r2_2 = Test-Requirement `
    -Name "2.2" `
    -Description "Alert APIHighErrorRate tồn tại" `
    -Test {
        $rule = kubectl get prometheusrule api-slo-alerts -n demo -o json 2>$null | ConvertFrom-Json
        $alert = $rule.spec.groups[0].rules | Where-Object { $_.alert -eq "APIHighErrorRate" }
        if ($alert) {
            Write-Host "    → Alert name: $($alert.alert)" -ForegroundColor Gray
            Write-Host "    → Severity: $($alert.labels.severity)" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r2_3 = Test-Requirement `
    -Name "2.3" `
    -Description "AlertmanagerConfig có email receiver" `
    -Test {
        $config = kubectl get alertmanagerconfig api-email-alerts -n demo -o json 2>$null | ConvertFrom-Json
        if ($config.spec.receivers) {
            $emailReceiver = $config.spec.receivers | Where-Object { $_.emailConfigs }
            if ($emailReceiver) {
                $emailTo = $emailReceiver.emailConfigs[0].to
                Write-Host "    → Email nhận: $emailTo" -ForegroundColor Gray
                return $true
            }
        }
        return $false
    }

$r2_4 = Test-Requirement `
    -Name "2.4" `
    -Description "SMTP Secret đã được tạo" `
    -Test {
        $secret = kubectl get secret alertmanager-email-secret -n demo 2>$null
        if ($secret) {
            Write-Host "    → Secret tồn tại" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "    ⚠️ Cần tạo secret: kubectl create secret generic alertmanager-email-secret -n demo --from-literal=password='YOUR_SMTP_PASSWORD'" -ForegroundColor Yellow
            return $false
        }
    }

$r2_5 = Test-Requirement `
    -Name "2.5" `
    -Description "ServiceMonitor scrape metrics từ API" `
    -Test {
        $sm = kubectl get servicemonitor api -n demo -o json 2>$null | ConvertFrom-Json
        if ($sm.spec.endpoints) {
            $interval = $sm.spec.endpoints[0].interval
            Write-Host "    → Scrape interval: $interval" -ForegroundColor Gray
            return $true
        }
        return $false
    }

# ============================================
# YÊU CẦU 3: CANARY TỰ ĐỘNG
# ============================================
Write-Host "`n3️⃣ YÊU CẦU 3: Canary Tự động" -ForegroundColor Magenta
Write-Host "─────────────────────────────────" -ForegroundColor Magenta

$r3_1 = Test-Requirement `
    -Name "3.1" `
    -Description "Rollout sử dụng Canary strategy" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if ($rollout.spec.strategy.canary) {
            Write-Host "    → Strategy: Canary" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r3_2 = Test-Requirement `
    -Name "3.2" `
    -Description "Canary có AnalysisTemplate" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        $hasAnalysis = $false
        foreach ($step in $rollout.spec.strategy.canary.steps) {
            if ($step.analysis) {
                $hasAnalysis = $true
                $templateName = $step.analysis.templates[0].templateName
                Write-Host "    → AnalysisTemplate: $templateName" -ForegroundColor Gray
                break
            }
        }
        return $hasAnalysis
    }

$r3_3 = Test-Requirement `
    -Name "3.3" `
    -Description "AnalysisTemplate tồn tại và có metrics" `
    -Test {
        $template = kubectl get analysistemplate api-success-rate -n demo -o json 2>$null | ConvertFrom-Json
        if ($template.spec.metrics) {
            $metricCount = $template.spec.metrics.Count
            Write-Host "    → Số lượng metrics: $metricCount" -ForegroundColor Gray
            foreach ($metric in $template.spec.metrics) {
                Write-Host "      • $($metric.name): successCondition=$($metric.successCondition)" -ForegroundColor Gray
            }
            return $true
        }
        return $false
    }

$r3_4 = Test-Requirement `
    -Name "3.4" `
    -Description "Canary có abortScaleDownDelaySeconds (auto rollback)" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if ($rollout.spec.strategy.canary.abortScaleDownDelaySeconds) {
            $delay = $rollout.spec.strategy.canary.abortScaleDownDelaySeconds
            Write-Host "    → Abort delay: ${delay}s" -ForegroundColor Gray
            return $true
        }
        return $false
    }

$r3_5 = Test-Requirement `
    -Name "3.5" `
    -Description "Canary KHÔNG có scaleDownDelaySeconds (cần traffic routing)" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        if (-not $rollout.spec.strategy.canary.scaleDownDelaySeconds) {
            Write-Host "    → Cấu hình đúng (không dùng scaleDownDelaySeconds)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "    ⚠️ Có scaleDownDelaySeconds → Cần xóa (chỉ dùng với traffic routing)" -ForegroundColor Yellow
            return $false
        }
    }

$r3_6 = Test-Requirement `
    -Name "3.6" `
    -Description "Rollout hiện tại ở trạng thái Healthy" `
    -Test {
        $rollout = kubectl get rollout api -n demo -o json 2>$null | ConvertFrom-Json
        $status = $rollout.status.phase
        Write-Host "    → Status: $status" -ForegroundColor Gray
        if ($status -eq "Healthy") {
            return $true
        } elseif ($status -eq "Progressing") {
            Write-Host "    ℹ️ Rollout đang chạy, chờ hoàn thành" -ForegroundColor Cyan
            return $true
        }
        return $false
    }

# ============================================
# TỔNG KẾT
# ============================================
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "📊 TỔNG KẾT" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$total = 0
$passed = 0

$results = @{
    "YÊU CẦU 1 (GitOps)" = @($r1_1, $r1_2, $r1_3)
    "YÊU CẦU 2 (SLO+Alert)" = @($r2_1, $r2_2, $r2_3, $r2_4, $r2_5)
    "YÊU CẦU 3 (Canary)" = @($r3_1, $r3_2, $r3_3, $r3_4, $r3_5, $r3_6)
}

foreach ($req in $results.Keys) {
    $reqPassed = ($results[$req] | Where-Object { $_ -eq $true }).Count
    $reqTotal = $results[$req].Count
    $total += $reqTotal
    $passed += $reqPassed
    
    $percent = [math]::Round(($reqPassed / $reqTotal) * 100)
    $status = if ($reqPassed -eq $reqTotal) { "✅" } else { "⚠️" }
    
    Write-Host "`n$status $req : $reqPassed/$reqTotal ($percent%)" -ForegroundColor $(if ($reqPassed -eq $reqTotal) { "Green" } else { "Yellow" })
}

$totalPercent = [math]::Round(($passed / $total) * 100)
Write-Host "`n─────────────────────────────────" -ForegroundColor Cyan
Write-Host "TỔNG: $passed/$total tests passed ($totalPercent%)" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })

if ($passed -eq $total) {
    Write-Host "`n🎉 HOÀN HẢO! Tất cả yêu cầu đã đáp ứng!" -ForegroundColor Green
    Write-Host "Tiếp theo: Chạy các test thực tế trong TEST-GUIDE.md" -ForegroundColor Cyan
} else {
    Write-Host "`n⚠️ Còn thiếu một số cấu hình. Xem hướng dẫn chi tiết bên trên." -ForegroundColor Yellow
}

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host ""
