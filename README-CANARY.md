# 🚀 GitOps Canary Deployment với Auto-Abort & SLO Monitoring

## 📌 Tổng quan Challenge

Challenge này thực hiện **triển khai canary tự động** với các tính năng:

1. ✅ **Mọi thay đổi qua Git** - ArgoCD tự động sync, rollback < 5 phút với `git revert`
2. ✅ **SLO + Alert tự động** - Giám sát chất lượng, gửi email khi vi phạm SLO
3. ✅ **Canary tự động abort** - AnalysisTemplate tự đánh giá, rollback nếu phát hiện lỗi

---

## 🎯 Kiến trúc giải pháp

```
┌─────────────┐       ┌──────────────┐       ┌─────────────┐
│   Git Push  │──────>│   ArgoCD     │──────>│ Kubernetes  │
│  (api.yaml) │       │ Auto-Sync    │       │  Rollout    │
└─────────────┘       └──────────────┘       └─────────────┘
                                                     │
                                                     ▼
                            ┌────────────────────────────────────┐
                            │   Argo Rollouts Canary Strategy   │
                            │                                    │
                            │  Step 1: 25% traffic → Analysis   │
                            │  Step 2: 50% traffic → Analysis   │
                            │  Step 3: 100% (promote)            │
                            │                                    │
                            │  Auto-Abort nếu analysis FAIL      │
                            └────────────────────────────────────┘
                                             │
                                             ▼
                            ┌────────────────────────────────────┐
                            │      AnalysisTemplate              │
                            │  (Đánh giá metrics từ Prometheus)  │
                            │                                    │
                            │  ✓ Success Rate >= 95%             │
                            │  ✓ Error Rate < 5%                 │
                            │  ✓ Request Rate > 0.1/s            │
                            │                                    │
                            │  Fail 2/5 lần → AUTO ABORT         │
                            └────────────────────────────────────┘
                                             │
                                             ▼
                            ┌────────────────────────────────────┐
                            │     Prometheus + Alertmanager      │
                            │                                    │
                            │  SLO: Success Rate >= 95%          │
                            │  Alert: Fire sau 2 phút vi phạm    │
                            │  Action: Gửi email tới admin       │
                            └────────────────────────────────────┘
```

---

## 📊 Chi tiết Metrics & Query

### 1️⃣ Success Rate (Tỷ lệ thành công)

**Mục đích**: Đo % request thành công (không lỗi 5xx)

**Prometheus Query**:
```promql
sum(rate(flask_http_request_total{status!~"5..", app="api", pod=~"api-[a-z0-9]+-[a-z0-9]+"}[1m])) 
/ 
sum(rate(flask_http_request_total{app="api", pod=~"api-[a-z0-9]+-[a-z0-9]+"}[1m]))
```

**Giải thích**:
- `flask_http_request_total{status!~"5.."}` = Đếm request KHÔNG có status 5xx (thành công)
- `rate(...[1m])` = Tính tốc độ request/giây trong 1 phút qua
- `sum()` = Tổng hợp tất cả pods
- Chia cho tổng request = % thành công

**Ngưỡng**: 
- ✅ **Thành công**: >= 95% (0.95)
- ❌ **Fail**: < 95% → Abort deployment

**Tại sao 95%?**
- Industry standard cho high-availability services
- Cho phép 5% lỗi do network issues, retries, user errors
- Đủ nghiêm ngặt để bắt được regression bugs

---

### 2️⃣ Error Rate (Tỷ lệ lỗi)

**Mục đích**: Đo % request lỗi server (5xx errors)

**Prometheus Query**:
```promql
sum(rate(flask_http_request_total{status=~"5..", app="api", pod=~"api-[a-z0-9]+-[a-z0-9]+"}[1m])) 
/ 
sum(rate(flask_http_request_total{app="api", pod=~"api-[a-z0-9]+-[a-z0-9]+"}[1m]))
```

**Giải thích**:
- `status=~"5.."` = Regex match các status code 500-599
- Tính % request lỗi server

**Ngưỡng**:
- ✅ **Thành công**: < 5% (0.05)
- ❌ **Fail**: >= 5% → Abort deployment

**Tại sao 5%?**
- Đảo ngược của success rate (100% - 95% = 5%)
- Kiểm tra kép để tăng độ tin cậy

---

### 3️⃣ Request Rate (Lưu lượng traffic)

**Mục đích**: Đảm bảo có traffic thật để metrics không bị "false positive"

**Prometheus Query**:
```promql
sum(rate(flask_http_request_total{app="api", pod=~"api-[a-z0-9]+-[a-z0-9]+"}[1m]))
```

**Ngưỡng**:
- ✅ **Thành công**: > 0.1 request/s
- ❌ **Fail**: Không có traffic → Không thể đánh giá

**Tại sao cần metric này?**
- Nếu không có traffic, success rate = 100% (vì không có request nào fail)
- Tránh "silent deployment" - deploy mà không ai dùng

---

## 🎛️ AnalysisTemplate Configuration

### Cơ chế hoạt động

```yaml
metrics:
  - name: success-rate
    interval: 30s        # Đo mỗi 30 giây
    count: 5             # Đo 5 lần = 2.5 phút
    failureLimit: 2      # Cho phép fail tối đa 2/5 lần
    successCondition: result >= 0.95
```

**Timeline**:
```
T=0s   → Đo lần 1: Pass ✓
T=30s  → Đo lần 2: Pass ✓
T=60s  → Đo lần 3: FAIL ✗ (1/2)
T=90s  → Đo lần 4: FAIL ✗ (2/2) → ABORT! 🚨
```

**Tại sao failureLimit=2?**
- Cho phép 1-2 lần đo bất thường do network jitter
- Lần thứ 3 fail → Chắc chắn có vấn đề → Abort ngay

**Tại sao count=5?**
- Tổng thời gian đánh giá = 5 × 30s = 2.5 phút
- Đủ để phát hiện lỗi nhưng không quá lâu
- Balance giữa safety và speed

---

## 🚨 SLO & Alerting

### SLO Definition

**Service Level Objective (SLO)**:
> API phải có **Success Rate >= 95%** trong 5 phút liên tục

**PrometheusRule**:
```yaml
- alert: APIHighErrorRate
  expr: |
    (sum(rate(flask_http_request_total{app="api", status!~"5.."}[5m])) 
     / 
     sum(rate(flask_http_request_total{app="api"}[5m]))
    ) < 0.95
  for: 2m          # Fire sau 2 phút vi phạm
```

**Giải thích**:
- `[5m]` = Đo trong 5 phút sliding window
- `for: 2m` = Phải vi phạm liên tục 2 phút mới fire
- Tránh false alarm do spike tạm thời

### Alert Flow

```
1. Metrics vi phạm SLO (Success Rate < 95%)
          ↓
2. Chờ 2 phút (for: 2m) → Confirm không phải spike
          ↓
3. Fire alert → Gửi tới Alertmanager
          ↓
4. Alertmanager gửi email tới admin
          ↓
5. Email chứa:
   - Summary: Tình trạng hiện tại
   - Description: Hướng dẫn debug
   - Runbook link: Các bước khắc phục
```

### Email Configuration

**Cần cấu hình**:
1. SMTP server (Gmail, SendGrid, AWS SES...)
2. Email nhận alert
3. Secret chứa SMTP password

**Bước setup**:
```bash
# 1. Tạo secret
kubectl create secret generic alertmanager-email-secret \
  -n demo \
  --from-literal=password='your-app-password'

# 2. Sửa email trong slo-alert.yaml
# Tìm dòng: to: 'your-email@example.com'
# Thay = email của bạn

# 3. Apply config
kubectl apply -f k8s-api/slo-alert.yaml
```

**Note**: Nếu dùng Gmail, cần bật [App Password](https://myaccount.google.com/apppasswords)

---

## 🔄 Canary Deployment Flow

### Bước 1: Deploy phiên bản mới

```bash
# Sửa image version trong api.yaml
image: w9-api:2  # old: w9-api:1

# Push lên Git
git add k8s-api/api.yaml
git commit -m "feat: deploy api v2"
git push
```

### Bước 2: ArgoCD auto-sync

ArgoCD phát hiện thay đổi → Sync ngay lập tức (< 30s)

```bash
# Xem trạng thái
kubectl argo rollouts get rollout api -n demo

# Hoặc xem trong Argo Rollouts Dashboard
kubectl argo rollouts dashboard
```

### Bước 3: Canary Analysis (Tự động)

```
Phase 1: 25% Traffic
├─ 30s warmup
├─ Analysis run (2.5 phút)
│  ├─ Success rate: 98% ✓
│  ├─ Error rate: 2% ✓
│  └─ Request rate: 5 req/s ✓
└─ PASS → Tiếp tục

Phase 2: 50% Traffic
├─ 30s warmup
├─ Analysis run (2.5 phút)
│  ├─ Success rate: 97% ✓
│  ├─ Error rate: 3% ✓
│  └─ Request rate: 10 req/s ✓
└─ PASS → Tiếp tục

Phase 3: 100% Traffic
└─ Promote completed! 🎉
```

### Bước 4: Nếu phát hiện lỗi → Auto-Abort

```
Phase 1: 25% Traffic
├─ 30s warmup
├─ Analysis run
│  ├─ T=0s:  Success 92% ✗ FAIL (1/2)
│  ├─ T=30s: Success 91% ✗ FAIL (2/2)
│  └─ ABORT TRIGGERED! 🚨
├─ Scale down canary pods
├─ Route 100% traffic về stable version
└─ Rollback completed!
```

**Tự động**:
- Không cần can thiệp thủ công
- Rollback trong < 1 phút
- Stable version vẫn chạy nguyên vẹn

---

## 🛠️ Testing & Demo

### Test Case 1: Deploy bản tốt (SUCCESS)

```bash
# 1. Deploy version với ERROR_RATE=0 (không lỗi)
# Sửa trong k8s-api/api.yaml:
env:
  - name: ERROR_RATE
    value: "0"        # ← 0% lỗi
  - name: VERSION
    value: "v4-good"

# 2. Commit & push
git add -A
git commit -m "test: deploy good version (0% error)"
git push

# 3. Xem rollout tự động promote
kubectl argo rollouts get rollout api -n demo --watch

# 4. Kết quả mong đợi:
# ✓ Step 1: 25% → Analysis PASS → Continue
# ✓ Step 2: 50% → Analysis PASS → Continue
# ✓ Step 3: 100% → Deployment completed! 🎉
```

**Expected Output**:
```
Name:            api
Namespace:       demo
Status:          ✔ Healthy
Strategy:        Canary
  Step:          6/6
  SetWeight:     100
  ActualWeight:  100
Images:          w9-api:2 (stable)
Replicas:
  Desired:       4
  Current:       4
  Updated:       4
  Ready:         4
  Available:     4

AnalysisRuns:
  ✔ api-success-rate-25-xxxxx (Success)
  ✔ api-success-rate-50-xxxxx (Success)
```

---

### Test Case 2: Deploy bản lỗi (AUTO-ABORT)

```bash
# 1. Deploy version với ERROR_RATE=0.5 (50% lỗi)
# Sửa trong k8s-api/api.yaml:
env:
  - name: ERROR_RATE
    value: "0.5"      # ← 50% request sẽ trả về 500 error
  - name: VERSION
    value: "v5-bad"

# 2. Commit & push
git add -A
git commit -m "test: deploy bad version (50% error) - expect auto-abort"
git push

# 3. Xem rollout tự động abort
kubectl argo rollouts get rollout api -n demo --watch

# 4. Kết quả mong đợi:
# ✓ Step 1: 25% → Analysis FAIL → ABORT! 🚨
# ✓ Rollback về v4-good
# ✓ Canary pods scaled to 0
```

**Expected Output**:
```
Name:            api
Namespace:       demo
Status:          ✖ Degraded
Message:         AnalysisRun 'api-success-rate-25-xxxxx' failed
Strategy:        Canary
  Step:          0/6 (Aborted)
  SetWeight:     0
  ActualWeight:  0
Images:          w9-api:1 (stable)
Replicas:
  Desired:       4
  Current:       4
  Updated:       0  ← Canary đã bị xóa
  Ready:         4
  Available:     4

AnalysisRuns:
  ✖ api-success-rate-25-xxxxx (Failed)
    Metric: success-rate
    Phase: Failed
    Message: Metric 'success-rate' failed: result 0.52 < threshold 0.95 (2 times)
```

---

### Test Case 3: Rollback thủ công qua Git

```bash
# Nếu deployment đã promote nhưng phát hiện bug sau
# → Rollback trong < 5 phút

# 1. Git revert commit cuối
git log --oneline          # Xem commit hash
git revert HEAD           # Revert commit mới nhất
git push

# 2. ArgoCD tự động sync về version cũ
# Thời gian: < 30s (ArgoCD sync) + 2-3 phút (Rollout complete)
# Tổng: < 5 phút ✓

# 3. Verify
kubectl argo rollouts get rollout api -n demo
# Image: w9-api:1 (reverted)
```

---

## 📸 Chứng minh (Screenshot Checklist)

### 1. Canary Auto-Abort
- [ ] Screenshot: `kubectl argo rollouts get rollout api -n demo`
  - Show: Status = Degraded, AnalysisRun = Failed
- [ ] Screenshot: AnalysisRun detail
  ```bash
  kubectl get analysisrun -n demo -l rollout=api
  kubectl describe analysisrun <name> -n demo
  ```
  - Show: Metric failed, Message về threshold

### 2. Alert Email
- [ ] Screenshot: Email nhận được từ Alertmanager
  - Subject: 🚨 [CRITICAL] APIHighErrorRate
  - Body: Có description và runbook link

### 3. Prometheus Metrics
- [ ] Screenshot: Grafana/Prometheus query
  - Query: Success rate < 95%
  - Timeline: Alert firing

### 4. Git Rollback
- [ ] Screenshot: Git log
  ```bash
  git log --oneline --graph -10
  ```
  - Show: Revert commit
- [ ] Screenshot: ArgoCD UI
  - Show: Synced to reverted commit

---

## 🎥 Clip Demo Script

**Thời lượng**: 3-5 phút

### Timeline:

```
00:00 - 00:30  │ Giới thiệu architecture diagram
00:30 - 01:00  │ Show code: AnalysisTemplate metrics
01:00 - 02:00  │ Demo 1: Deploy good version → Auto promote
02:00 - 03:30  │ Demo 2: Deploy bad version → Auto abort
03:30 - 04:30  │ Demo 3: Git revert → Rollback < 5'
04:30 - 05:00  │ Show alert email + wrap up
```

### Recording Commands:

```bash
# Terminal 1: Watch rollout
kubectl argo rollouts get rollout api -n demo --watch

# Terminal 2: Generate traffic (để có metrics)
while true; do 
  curl http://<api-service-url>/
  sleep 0.1
done

# Terminal 3: Git operations
git log --oneline --graph
git commit -m "..."
git push
git revert HEAD
```

---

## 🔧 Troubleshooting

### Vấn đề 1: Analysis luôn pass dù có lỗi

**Nguyên nhân**: Không có traffic → Metrics rỗng → False positive

**Giải pháp**: Thêm `request-rate` metric (đã có trong template)

---

### Vấn đề 2: Alert không gửi email

**Check**:
```bash
# 1. Xem Alertmanager config
kubectl get alertmanagerconfig -n demo

# 2. Xem secret
kubectl get secret alertmanager-email-secret -n demo -o yaml

# 3. Xem Alertmanager logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager

# 4. Test bằng curl
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
curl http://localhost:9093/-/healthy
```

**Common issues**:
- SMTP password sai → Check secret
- Firewall chặn port 587 → Test telnet
- Gmail App Password chưa bật → Vào Google Account settings

---

### Vấn đề 3: ArgoCD không sync

**Check**:
```bash
# 1. Xem ArgoCD application status
kubectl get application -n argocd api -o yaml

# 2. Check sync policy
# Phải có: automated: {prune: true, selfHeal: true}

# 3. Force sync
kubectl argo app sync api
```

---

## 📚 Tài liệu tham khảo

- [Argo Rollouts - Progressive Delivery](https://argoproj.github.io/argo-rollouts/)
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [Alertmanager Email Configuration](https://prometheus.io/docs/alerting/latest/configuration/#email_config)
- [SLO Best Practices - Google SRE Book](https://sre.google/workbook/implementing-slos/)

---

## ✅ Checklist hoàn thành Challenge

- [x] **Challenge 1**: Mọi thay đổi qua Git
  - [x] ArgoCD auto-sync enabled
  - [x] Git revert rollback < 5 phút
  
- [x] **Challenge 2**: SLO + Alert
  - [x] Định nghĩa 1 SLO (Success Rate >= 95%)
  - [x] PrometheusRule fire khi vi phạm
  - [x] Alertmanager gửi email
  
- [x] **Challenge 3**: Canary tự động
  - [x] AnalysisTemplate với Prometheus metrics
  - [x] Auto-abort khi metrics fail
  - [x] Tự động rollback về stable version
  - [x] README giải thích query & ngưỡng
  - [x] Script/guide để reproduce demo

---

## 🎓 Key Takeaways

1. **GitOps = Single Source of Truth**
   - Mọi thay đổi qua Git
   - Rollback = git revert (đơn giản, audit được)

2. **Metrics-driven Deployment**
   - Không tin tưởng code mới 100%
   - Để metrics quyết định promote hay abort
   - Automation > Manual testing

3. **Defense in Depth**
   - Layer 1: AnalysisTemplate (real-time abort)
   - Layer 2: SLO alerts (notify team)
   - Layer 3: Git revert (manual rollback)

4. **Progressive Delivery**
   - Canary = Giảm blast radius
   - 25% → 50% → 100% = Incremental risk
   - Fail fast, rollback faster

---

**Made with ❤️ for GitOps Challenge**

*Nếu có câu hỏi, mở issue hoặc liên hệ team!*
