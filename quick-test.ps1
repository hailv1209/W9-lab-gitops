# 🚀 Quick Test - Kiểm tra nhanh từng yêu cầu
# Usage: .\quick-test.ps1 [1|2|3|all]

param(
    [string]$TestNumber = "all"
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "🚀 QUICK TEST CANARY DEPLOYMENT" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# ============================================
# TEST 1: GITOPS
# ============================================
function Test-GitOps {
    Write-Host "`n1️⃣ TEST GITOPS & ROLLBACK" -ForegroundColor Magenta
    Write-Host "─────────────────────────────────" -ForegroundColor Magenta
    
    Write-Host "`n📌 Kiểm tra ArgoCD Application:" -ForegroundColor Yellow
    kubectl get app api -n argocd
    
    Write-Host "`n📌 Kiểm tra Rollout hiện tại:" -ForegroundColor Yellow
    kubectl argo rollouts get rollout api -n demo
    
    Write-Host "`n✅ HƯỚNG DẪN TEST THỦ CÔNG:" -ForegroundColor Green
    Write-Host "1. Sửa file k8s-api\api.yaml (dòng 27):"
    Write-Host "   VERSION: 'v3' → 'v4-test'"
    Write-Host ""
    Write-Host "2. Commit và push:"
    Write-Host "   git add k8s-api\api.yaml"
    Write-Host "   git commit -m 'test: deploy v4'"
    Write-Host "   git push"
    Write-Host ""
    Write-Host "3. Theo dõi deploy:"
    Write-Host "   kubectl argo rollouts get rollout api -n demo -w"
    Write-Host ""
    Write-Host "4. Rollback (đo thời gian):"
    Write-Host "   `$start = Get-Date"
    Write-Host "   git revert HEAD --no-edit && git push"
    Write-Host "   kubectl argo rollouts get rollout api -n demo -w"
    Write-Host "   `$end = Get-Date"
    Write-Host "   (`$end - `$start).TotalMinutes"
    Write-Host ""
    Write-Host "✅ KẾT QUẢ MONG ĐỢI: Rollback hoàn thành < 5 phút" -ForegroundColor Green
}

# ============================================
# TEST 2: SLO + ALERT
# ============================================
function Test-Alert {
    Write-Host "`n2️⃣ TEST SLO + ALERT → EMAIL" -ForegroundColor Magenta
    Write-Host "─────────────────────────────────" -ForegroundColor Magenta
    
    Write-Host "`n📌 Kiểm tra PrometheusRule:" -ForegroundColor Yellow
    kubectl get prometheusrule api-slo-alerts -n demo
    
    Write-Host "`n📌 Kiểm tra AlertmanagerConfig:" -ForegroundColor Yellow
    kubectl get alertmanagerconfig api-email-alerts -n demo
    
    Write-Host "`n📌 Kiểm tra SMTP Secret:" -ForegroundColor Yellow
    $secret = kubectl get secret alertmanager-email-secret -n demo 2>$null
    if ($secret) {
        Write-Host "✅ Secret đã tồn tại" -ForegroundColor Green
    } else {
        Write-Host "❌ Secret chưa tạo!" -ForegroundColor Red
        Write-Host ""
        Write-Host "⚠️ CẦN TẠO SECRET TRƯỚC:" -ForegroundColor Yellow
        Write-Host "1. Tạo Gmail App Password: https://myaccount.google.com/apppasswords"
        Write-Host "2. Chạy lệnh:"
        Write-Host "   kubectl create secret generic alertmanager-email-secret ``"
        Write-Host "     -n demo ``"
        Write-Host "     --from-literal=password='YOUR-16-CHAR-PASSWORD'"
        Write-Host ""
        return
    }
    
    Write-Host "`n📌 Kiểm tra ServiceMonitor:" -ForegroundColor Yellow
    kubectl get servicemonitor api -n demo
    
    Write-Host "`n✅ HƯỚNG DẪN TEST THỦ CÔNG:" -ForegroundColor Green
    Write-Host "1. Deploy bản có lỗi (ERROR_RATE=0.3):"
    Write-Host "   - Sửa k8s-api\api.yaml dòng 24: ERROR_RATE: '0.3'"
    Write-Host "   - git add k8s-api\api.yaml"
    Write-Host "   - git commit -m 'test: trigger alert'"
    Write-Host "   - git push"
    Write-Host ""
    Write-Host "2. Gửi traffic để tạo metrics:"
    Write-Host "   `$ip = kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'"
    Write-Host "   for (`$i=1; `$i -le 200; `$i++) {"
    Write-Host "       try { Invoke-RestMethod http://`${ip}:8080/api/data } catch {}"
    Write-Host "       Start-Sleep -Milliseconds 100"
    Write-Host "   }"
    Write-Host ""
    Write-Host "3. Kiểm tra alert trong Prometheus:"
    Write-Host "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    Write-Host "   Mở: http://localhost:9090/alerts"
    Write-Host ""
    Write-Host "4. Đợi ~2-5 phút và kiểm tra email: haileab542@gmail.com"
    Write-Host ""
    Write-Host "✅ KẾT QUẢ MONG ĐỢI: Nhận email với subject '[CRITICAL] APIHighErrorRate'" -ForegroundColor Green
}

# ============================================
# TEST 3: CANARY TỰ ĐỘNG
# ============================================
function Test-Canary {
    Write-Host "`n3️⃣ TEST CANARY TỰ ĐỘNG" -ForegroundColor Magenta
    Write-Host "─────────────────────────────────" -ForegroundColor Magenta
    
    Write-Host "`n📌 Kiểm tra AnalysisTemplate:" -ForegroundColor Yellow
    kubectl get analysistemplate api-success-rate -n demo
    
    Write-Host "`n📌 Cấu hình Canary hiện tại:" -ForegroundColor Yellow
    $rollout = kubectl get rollout api -n demo -o json | ConvertFrom-Json
    Write-Host "Strategy: Canary"
    Write-Host "Steps: $($rollout.spec.strategy.canary.steps.Count)"
    Write-Host "abortScaleDownDelaySeconds: $($rollout.spec.strategy.canary.abortScaleDownDelaySeconds)"
    
    Write-Host "`n📌 Trạng thái Rollout hiện tại:" -ForegroundColor Yellow
    kubectl argo rollouts status rollout api -n demo
    
    Write-Host "`n✅ TEST 3A: CANARY THÀNH CÔNG (Bản tốt → 100%)" -ForegroundColor Green
    Write-Host "─────────────────────────────────"
    Write-Host "1. Deploy bản tốt:"
    Write-Host "   - Sửa k8s-api\api.yaml:"
    Write-Host "     • ERROR_RATE: '0'"
    Write-Host "     • VERSION: 'v5-good'"
    Write-Host "   - git add k8s-api\api.yaml && git commit -m 'test: good version' && git push"
    Write-Host ""
    Write-Host "2. Mở terminal thứ 2, gửi traffic liên tục:"
    Write-Host "   `$ip = kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'"
    Write-Host "   while (`$true) {"
    Write-Host "       Invoke-RestMethod http://`${ip}:8080/api/data | Out-Null"
    Write-Host "       Start-Sleep -Milliseconds 500"
    Write-Host "   }"
    Write-Host ""
    Write-Host "3. Terminal chính, theo dõi Rollout:"
    Write-Host "   kubectl argo rollouts get rollout api -n demo -w"
    Write-Host ""
    Write-Host "📊 QUAN SÁT:"
    Write-Host "   Step 1: setWeight 25%     ✅"
    Write-Host "   Step 2: pause 30s         ⏸️"
    Write-Host "   Step 3: analysis          🔍 success-rate ≥ 95%"
    Write-Host "   Step 4: setWeight 50%     ✅"
    Write-Host "   Step 5: pause 30s         ⏸️"
    Write-Host "   Step 6: analysis          🔍 success-rate ≥ 95%"
    Write-Host "   Step 7: setWeight 100%    🎉 PROMOTED"
    Write-Host ""
    Write-Host "✅ KẾT QUẢ: Status = Healthy, Image = v5-good (stable)" -ForegroundColor Green
    
    Write-Host "`n✅ TEST 3B: CANARY TỰ ĐỘNG ABORT (Bản lỗi → Rollback)" -ForegroundColor Green
    Write-Host "─────────────────────────────────"
    Write-Host "1. Deploy bản lỗi:"
    Write-Host "   - Sửa k8s-api\api.yaml:"
    Write-Host "     • ERROR_RATE: '0.5' (50% lỗi)"
    Write-Host "     • VERSION: 'v6-bad'"
    Write-Host "   - git add k8s-api\api.yaml && git commit -m 'test: bad version' && git push"
    Write-Host ""
    Write-Host "2. Gửi traffic liên tục (terminal 2, giống trên)"
    Write-Host ""
    Write-Host "3. Theo dõi Rollout (terminal chính):"
    Write-Host "   kubectl argo rollouts get rollout api -n demo -w"
    Write-Host ""
    Write-Host "📊 QUAN SÁT:"
    Write-Host "   Step 1: setWeight 25%     ✅"
    Write-Host "   Step 2: pause 30s         ⏸️"
    Write-Host "   Step 3: analysis          🔍"
    Write-Host "      ├─ success-rate: ❌ ~50% (< 95%)"
    Write-Host "      ├─ error-rate: ❌ ~50% (> 5%)"
    Write-Host "      └─ FAILED 2/2 times"
    Write-Host "   → 🚨 AUTO ABORT"
    Write-Host "   → ⏳ Wait 30s (abortScaleDownDelaySeconds)"
    Write-Host "   → 🔄 Scale down canary pods"
    Write-Host "   → ✅ Rollback to stable: v5-good"
    Write-Host ""
    Write-Host "✅ KẾT QUẢ: Status = Healthy, Image vẫn là v5-good (stable)" -ForegroundColor Green
    Write-Host "✅ Không có downtime, stable pods vẫn phục vụ traffic" -ForegroundColor Green
}

# ============================================
# MAIN
# ============================================
switch ($TestNumber) {
    "1" { Test-GitOps }
    "2" { Test-Alert }
    "3" { Test-Canary }
    "all" {
        Test-GitOps
        Test-Alert
        Test-Canary
    }
    default {
        Write-Host "❌ Invalid test number. Usage: .\quick-test.ps1 [1|2|3|all]" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "📚 TÀI LIỆU CHI TIẾT: Xem TEST-GUIDE.md" -ForegroundColor Cyan
Write-Host "🤖 TEST TỰ ĐỘNG: Chạy .\test-requirements.ps1" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
