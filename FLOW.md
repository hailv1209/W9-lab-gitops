# Flow & Syntax Reference — W9 GitOps Lab

---

## Mục lục

1. [Tổng quan flow toàn hệ thống](#1-tổng-quan-flow-toàn-hệ-thống)
2. [Flow chi tiết từng yêu cầu](#2-flow-chi-tiết-từng-yêu-cầu)
3. [Giải thích cú pháp `k8s-api/api.yaml`](#3-giải-thích-cú-pháp-k8s-apiapiyaml)
4. [Giải thích cú pháp `k8s-api/analysis-template.yaml`](#4-giải-thích-cú-pháp-k8s-apianalysis-templateyaml)
5. [Giải thích cú pháp `k8s-api/slo-alert.yaml`](#5-giải-thích-cú-pháp-k8s-apislo-alertyaml)
6. [Giải thích cú pháp `app/app.py`](#6-giải-thích-cú-pháp-appapppy)
7. [Giải thích cú pháp `send_rapid_bug.py`](#7-giải-thích-cú-pháp-send_rapid_bugpy)

---

## 1. Tổng quan flow toàn hệ thống

### Sơ đồ luồng dữ liệu và quyết định

```
 DEPLOY BẢN MỚI
 │
 ▼
┌──────────────────────────────────────────────────────────────┐
│  git push → Git Remote → ArgoCD sync (~30s)                  │
└────────────────────────────┬─────────────────────────────────┘
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Argo Rollout: api (namespace: demo)                         │
│                                                              │
│  replicas: 4                                                │
│                                                              │
│  Stable pods (version cũ)    ──── phục vụ 100% traffic     │
│  Canary pods (version mới)   ──── phục vụ % theo setWeight │
└────────────────────────────┬─────────────────────────────────┘
                             │
                    setWeight: 25 → 50 → 100
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  AnalysisTemplate: api-success-rate                            │
│                                                              │
│  Prometheus query mỗi 30s × 5 lần:                          │
│    ├─ success-rate >= 95% ?                                 │
│    └─ error-rate < 5% ?                                     │
│                                                              │
│    ✅ PASS 2 lần → tiếp tục canary                          │
│    ❌ FAIL 2 lần → AUTO ABORT → rollback về stable         │
└────────────────────────────┬─────────────────────────────────┘
                             │
                   metrics (Flask app expose /metrics)
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  ServiceMonitor: scrape /metrics mỗi 15s                     │
│  → Prometheus (kube-prometheus-stack)                        │
│                                                              │
│  PrometheusRule định nghĩa SLO:                             │
│    ├─ APIHighErrorRate (critical, for: 30s)                 │
│    └─ APIHighLatency    (warning, for: 1m)                  │
│                                                              │
│  Alert firing khi vi phạm SLO                                │
└────────────────────────────┬─────────────────────────────────┘
                             │ alert (label: app=api)
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Alertmanager: AlertmanagerConfig route theo app=api          │
│  → emailConfigs: SMTP Gmail                                   │
│  → 📧 gửi email về haileab542@gmail.com                     │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Flow chi tiết từng yêu cầu

### 2.1. Yêu cầu 1 — GitOps (Deploy & Rollback)

```
Bước 1: Developer sửa VERSION trong k8s-api/api.yaml
         image: w9-api:3  →  image: w9-api:4
         value: "v7"      →  value: "v8"

Bước 2: git add + git commit + git push
         → Git remote nhận commit mới

Bước 3: ArgoCD polling (mặc định 3 phút, đã config ~30s)
         → ArgoCD thấy Git ≠ Cluster
         → ArgoCD sync các YAML vào namespace demo

Bước 4: Argo Rollout nhận spec mới
         → Tạo Canary ReplicaSet (version mới, weight 25%)
         → Tạo Stable ReplicaSet (version cũ, weight 75%)

Bước 5: Canary steps chạy tự động
         25% → [pause 30s] → [analysis] → 50% → [pause 30s] → [analysis] → 100%

Rollback: git revert HEAD --no-edit && git push
         → ArgoCD sync ngược lại
         → Rollout revert về version cũ
```

### 2.2. Yêu cầu 2 — SLO + Alert (Giám sát & Email)

```
Flask app.py: app.get("/api/bug") → return 500
     │
     ▼
prometheus_flask_exporter: tự expose /metrics
     │
     ▼
ServiceMonitor: scrape /metrics mỗi 15s
     │
     ▼
Prometheus: ghi nhận metrics vào TSDB
     │
     ▼
PrometheusRule: chạy PromQL query mỗi 30s
     │
     ▼
Nếu success_rate < 0.95 trong 30s liên tục:
     │
     ▼
Alert APIHighErrorRate: FIRING
     │
     ▼
Alertmanager nhận alert (route: app=api)
     │
     ▼
emailConfigs: SMTP gửi email đến haileab542@gmail.com
```

### 2.3. Yêu cầu 3 — Canary tự động (AnalysisTemplate)

```
Deploy bản mới → Argo Rollout bắt đầu canary

Step 1: setWeight 25
        → 25% pods là canary (version mới)
        → 75% pods là stable (version cũ)
        → Service "api" tự động route theo tỷ lệ

Step 2: pause 30s
        → Chờ traffic ổn định vào canary
        → Prometheus tích lũy metrics đủ để đánh giá

Step 3: analysis (AnalysisTemplate api-success-rate)
        Prometheus query mỗi 30s:
          ├─ Lần 1 (30s): success-rate = ?
          ├─ Lần 2 (60s): success-rate = ?
          ├─ Lần 3 (90s): success-rate = ?
          ├─ Lần 4 (120s): success-rate = ?
          └─ Lần 5 (150s): success-rate = ?

        Nếu fail >= 2 lần → ABORT
        Nếu pass tất cả  → tiếp tục

Step 4: setWeight 50
        → 50% canary, 50% stable

Step 5: pause 30s + analysis lần 2

Step 6: setWeight 100 → Full promote
        → Canary trở thành stable
        → ReplicaSet cũ được scale down
```

---

## 3. Giải thích cú pháp `k8s-api/api.yaml`

File này chứa **3 Kubernetes resources** trong 1 file (phân cách bằng `---`).

---

### 3.1. Phần 1 — Rollout (ArgoCD Rollouts CRD)

```yaml
# apiVersion: argoproj.io/v1alpha1
# kind: Rollout
#   → Argo Rollouts CRD, KHÔNG phải native Kubernetes Deployment
#   → CRD được cài đặt bởi Argo Rollouts operator
#   → Mở rộng Deployment với chiến lược canary nâng cao

apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api                          # Tên rollout — duy nhất trong namespace
  namespace: demo
  labels:
    app: api
spec:
  replicas: 4                        # Số pod replicas — CẢ stable VÀ canary CỘNG LẠI = 4
                                    # Nghĩa là: stable=2, canary=2 khi ở 50%
  selector:
    matchLabels:
      app: api                       # Rollout tìm pods qua label này

  template:
    metadata:
      labels:
        app: api                     # Pods được tạo sẽ có label app=api
    spec:
      containers:
        - name: api
          image: w9-api:3            # Image của bản stable/canary
          imagePullPolicy: IfNotPresent  # Không pull lại nếu đã có local
          ports:
            - name: http            # Tên port — DÙNG TRONG ServiceMonitor!
              containerPort: 8080
          env:
            - name: VERSION
              value: "v7"           # Env var cho app hiển thị version
          readinessProbe:
            httpGet:
              path: /healthz        # Kubernetes check /healthz trước khi route traffic
              port: 8080
            initialDelaySeconds: 5  # Chờ 5s sau khi start mới bắt đầu check
            periodSeconds: 5        # Check mỗi 5s

  # ──────────────────────────────────────────────────────────────
  # STRATEGY CANARY — Chiến lược canary với AnalysisTemplate
  # ──────────────────────────────────────────────────────────────
  strategy:
    canary:
      # steps: thứ tự các bước canary tuần tự
      steps:
        # setWeight 25: 25% pods = canary (version mới)
        #              75% pods = stable (version cũ)
        - setWeight: 25

        # pause: dừng lại chờ. Duration = thời gian chờ.
        #        Không manual pause → không cần người approve
        - pause:
            duration: 30s           # 30 giây → đủ để Prometheus tích lũy metrics

        # analysis: chạy AnalysisTemplate để tự đánh giá
        #           NẾU pass → tiếp tục bước tiếp theo
        #           NẾU fail → abort rollout
        - analysis:
            templates:
              - templateName: api-success-rate
                                    # Tên AnalysisTemplate trong cùng namespace

        # Tiếp tục 50% → 100% tương tự
        - setWeight: 50
        - pause:
            duration: 30s
        - analysis:
            templates:
              - templateName: api-success-rate
        - setWeight: 100             # 100% → full promote, canary trở thành stable

      # analysis: BACKGROUND analysis — chạy LIÊN TỤC trong suốt canary
      #           Dùng để abort NGAY LẬP TỨC nếu metrics vi phạm
      analysis:
        templates:
          - templateName: api-success-rate
        startingStep: 2            # Bắt đầu monitor từ step index 2 (= step analysis đầu)
                                    # Index: 0=setWeight25, 1=pause, 2=analysis đầu
                                    # Nghĩa là: từ khi bắt đầu analysis đầu tiên,
                                    # Prometheus query liên tục → fail → abort ngay

      # abortScaleDownDelaySeconds: 30
      #   Khi abort: canary pods không xóa NGAY lập tức
      #   → Chờ 30s để engineer debug/logs
      #   → Sau 30s mới scale down về 0
      abortScaleDownDelaySeconds: 30
```

---

### 3.2. Phần 2 — Service (Kubernetes native)

```yaml
# apiVersion: v1
# kind: Service
#   → Native Kubernetes Service
#   → Argo Rollout DÙNG CHUNG Service này cho cả stable và canary pods
#   → Điều khiển traffic bằng Kubernetes Endpoints (thay đổi tỷ lệ replicas)

apiVersion: v1
kind: Service
metadata:
  name: api                          # Tên service — dùng trong ServiceMonitor selector
  namespace: demo
  labels:
    app: api
spec:
  type: ClusterIP                    # ClusterIP: chỉ truy cập trong cluster
  ports:
    - name: http                     # Tên port — PHẢI TRÙNG với port trong container
      port: 8080                     # Port cluster-wide (dùng để truy cập service)
      targetPort: http               # Chỉ đến container port có name="http" (=8080)
  selector:
    app: api                         # Tất cả pods có label app=api đều nhận traffic
                                    # CẢ stable VÀ canary pods đều match
                                    # → Argo Rollout kiểm soát tỷ lệ bằng Endpoints
```

---

### 3.3. Phần 3 — ServiceMonitor (Prometheus Operator CRD)

```yaml
# apiVersion: monitoring.coreos.com/v1
# kind: ServiceMonitor
#   → Prometheus Operator CRD
#   → Prometheus Operator NHẬN và quản lý ServiceMonitor này
#   → Tự động tạo Prometheus scrape config cho endpoint

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: demo                    # ServiceMonitor phải cùng namespace với Service
  labels:
    app: api
    release: prometheus              # ⚠️ RẤT QUAN TRỌNG
                                    # Prometheus Operator scrape ServiceMonitor
                                    # theo label "release: <name>"
                                    # Nếu thiếu → Prometheus không scrape
spec:
  selector:
    matchLabels:
      app: api                       # Chọn Service có label app=api
  endpoints:
    - port: http                     # Tên port trong Service (không phải số!)
                                    # → Prometheus scrape http://api:8080/metrics
      path: /metrics                 # Path endpoint metrics
      interval: 15s                  # Scrape mỗi 15 giây
```

---

## 4. Giải thích cú pháp `k8s-api/analysis-template.yaml`

```yaml
# apiVersion: argoproj.io/v1alpha1
# kind: AnalysisTemplate
#   → Argo Rollouts CRD
#   → Định nghĩa BỘ METRICS dùng để đánh giá canary
#   → Argo Rollouts gọi Prometheus để query metrics này

apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: api-success-rate            # Tên template — dùng trong Rollout spec
  namespace: demo
spec:
  metrics:
    # ──────────────────────────────────────────────────────────
    # METRIC 1: success-rate
    # Định nghĩa: Success Rate phải >= 95% (0.95)
    # ──────────────────────────────────────────────────────────
    - name: success-rate
      # interval: 30s
      #   → Argo Rollouts gọi Prometheus query MỖI 30 GIÂY
      #   → Prometheus tính rate trong [2m] window
      interval: 30s

      # count: 5
      #   → Tổng số lần query = 5
      #   → Tổng thời gian analysis = 5 × 30s = 150s = 2.5 phút
      count: 5

      # successCondition: result >= 0.95
      #   → Nếu result >= 0.95 → lần này PASS
      #   → Nếu result < 0.95 → lần này FAIL
      successCondition: result >= 0.95

      # failureLimit: 2
      #   → FAIL >= 2 lần → ARGO ROLLOUT ABORT
      #   → Đây là ngưỡng quyết định rollback
      failureLimit: 2

      # consecutiveErrorLimit: 5
      #   → Nếu Prometheus query LỖI liên tiếp 5 lần
      #   → Argo Rollouts coi như metric fail
      #   → Phòng trường hợp Prometheus down/network issue
      consecutiveErrorLimit: 5

      # provider: prometheus
      #   → Argo Rollouts gọi Prometheus API để query
      #   → Address phải là full DNS name của Prometheus service
      provider:
        prometheus:
          # Address: FQDN của Prometheus service trong cluster
          #   kube-prometheus-stack-prometheus = service name
          #   monitoring = namespace
          #   svc.cluster.local = cluster domain suffix
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

          # query: PromQL query — TRẢ VỀ 1 SỐ (scalar)
          query: |
            scalar(
              # Tử số: sum of rate requests KHÔNG phải 5xx
              # status!~"5.." = lọc status code KHÔNG bắt đầu bằng 5
              # VD: 200, 201, 301, 400, 404 đều được tính là thành công
              sum(rate(flask_http_request_total{status!~"5..",app="api"}[2m]))
              # or vector(1): Nếu không có request nào → trả 1 thay vì 0
              # Tránh 0/0 = NaN → fail metric
              or vector(1)
            )
            /
            scalar(
              # Mẫu số: sum of rate TẤT CẢ requests
              sum(rate(flask_http_request_total{app="api"}[2m]))
              or vector(1)          # Nếu không có request → 1/1 = 1.0 = 100% success
            )

    # ──────────────────────────────────────────────────────────
    # METRIC 2: error-rate
    # Định nghĩa: Error Rate (5xx) phải < 5% (< 0.05)
    # ──────────────────────────────────────────────────────────
    - name: error-rate
      interval: 30s
      count: 5
      # successCondition ngược lại: result < 0.05
      #   → error rate THẤP hơn ngưỡng → PASS
      #   → error rate CAO hơn ngưỡng → FAIL
      successCondition: result < 0.05
      failureLimit: 2
      consecutiveErrorLimit: 5
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          query: |
            scalar(
              # Tử số: sum of rate requests CÓ status 5xx
              # status=~"5.." = regex, match tất cả 500, 501, 502, ...
              sum(rate(flask_http_request_total{status=~"5..",app="api"}[2m]))
              # or vector(0): Không có lỗi → trả 0 thay vì NaN
              # 0/total = 0% error = PASS
              or vector(0)
            )
            /
            scalar(
              sum(rate(flask_http_request_total{app="api"}[2m]))
              or vector(1)
            )
```

---

## 5. Giải thích cú pháp `k8s-api/slo-alert.yaml`

File này chứa **3 resources** phân cách bằng `---`.

---

### 5.1. Phần 1 — PrometheusRule (SLO định nghĩa alerts)

```yaml
# apiVersion: monitoring.coreos.com/v1
# kind: PrometheusRule
#   → Prometheus Operator CRD
#   → Prometheus Operator quản lý rule này
#   → Prometheus server chạy PromQL query và fire alert khi điều kiện đúng

apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-slo-alerts
  namespace: demo
  labels:
    release: kube-prometheus-stack   # Prometheus Operator nhận rule theo label này
    app: api
spec:
  groups:
    - name: api-slo                  # Tên nhóm rules (group)
      interval: 30s                  # Prometheus đánh giá rule này mỗi 30s
      rules:
        # ──────────────────────────────────────────────────────
        # ALERT 1: APIHighErrorRate
        # ──────────────────────────────────────────────────────
        - alert: APIHighErrorRate
          # expr: PromQL query — nếu trả về TRUE → alert fire
          # Giải thích:
          #   Tử số: request thành công (không phải 5xx) trong 5 phút
          #   Mẫu số: tổng request trong 5 phút
          #   rate(): tính tốc độ trung bình (requests/second)
          #   [5m]: lookback window 5 phút
          #   result: thương số = success rate
          expr: |
            (
              sum(rate(flask_http_request_total{app="api", status!~"5.."}[5m]))
              /
              sum(rate(flask_http_request_total{app="api"}[5m]))
            ) < 0.95

          # for: 30s
          #   Prometheus CHỜ 30s sau khi expr=TRUE liên tục
          #   → Nếu 25s rồi success rate quay lại 95% → KHÔNG fire
          #   → Nếu 30s liên tục < 95% → FIRE
          #   → Mục đích: tránh false-positive từ spike tạm thời
          for: 30s

          # labels: metadata gắn vào alert
          #         Dùng để route trong AlertmanagerConfig
          labels:
            severity: critical        # Phân loại: critical / warning / info
            team: backend             # Team chịu trách nhiệm
            slo: availability         # Loại SLO: availability / latency / throughput
            app: api                  # App name → AlertmanagerConfig dùng để route

          # annotations: thông tin HIỂN THỊ trong alert
          #              Không dùng để route, chỉ để thông báo
          annotations:
            # summary: tiêu đề ngắn gọn (hiện trên email, Slack, ...)
            summary: "API Error Rate vượt ngưỡng SLO"

            # description: nội dung chi tiết
            # {{ $value }}: biến template — Prometheus thay bằng giá trị metric
            # humanizePercentage: filter, format giá trị thành % (VD: 0.94 → 94%)
            description: |
              Success rate hiện tại: {{ $value | humanizePercentage }}
              Ngưỡng SLO: 95%

              API đang có tỷ lệ lỗi cao, cần kiểm tra ngay!

              Các bước khắc phục:
              1. Kiểm tra logs: kubectl logs -n demo -l app=api --tail=100
              2. Kiểm tra rollout: kubectl argo rollouts get rollout api -n demo
              3. Rollback nếu cần: git revert HEAD && git push

              Dashboard: http://grafana/d/api-metrics
            runbook_url: "https://wiki.company.com/runbook/api-high-error-rate"

        # ──────────────────────────────────────────────────────
        # ALERT 2: APIHighLatency
        # ──────────────────────────────────────────────────────
        - alert: APIHighLatency
          # histogram_quantile(0.95, ...): tính percentile thứ 95
          #   → 95% requests có latency NHỎ HƠN giá trị này
          #   → 5% requests có latency LỚN HƠN giá trị này
          # flask_http_request_duration_seconds_bucket: histogram buckets
          #   → Đếm số requests theo latency range
          # by (le): group by label "le" (less than or equal bucket boundary)
          expr: |
            histogram_quantile(0.95,
              sum(rate(flask_http_request_duration_seconds_bucket{app="api"}[5m])) by (le)
            ) > 0.5                  # > 500ms → fire
          for: 1m                     # Chờ 1 phút (dài hơn error rate alert)
          labels:
            severity: warning
            team: backend
            slo: latency
            app: api
          annotations:
            summary: "API Latency cao"
            description: |
              P95 latency: {{ $value }}s
              Ngưỡng SLO: 500ms
```

---

### 5.2. Phần 2 — AlertmanagerConfig (Route & Email)

```yaml
# apiVersion: monitoring.coreos.com/v1alpha1
# kind: AlertmanagerConfig
#   → Prometheus Operator CRD
#   → Cấu hình Alertmanager: nhận alert, route đến receiver nào
#   → Prometheus Operator sync config vào Alertmanager pod

apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: api-email-alerts
  namespace: demo
  labels:
    alertmanagerConfig: main        # Alertmanager chính sẽ include config này
spec:
  # route: cấu hình routing tree
  #        Alertmanager duyệt tree từ root → leaf
  #        Alert đầu tiên match sẽ được gửi đến receiver tương ứng
  route:
    # groupBy: nhóm alerts theo labels — cùng group gửi trong 1 notification
    groupBy: ['alertname', 'severity']

    # groupWait: 30s
    #   → Khi alert mới fire, Alertmanager CHỜ 30s
    #   → Để gather thêm alerts cùng group
    #   → Gửi 1 notification cho tất cả thay vì nhiều notification lẻ tẻ
    groupWait: 30s

    # groupInterval: 5m
    #   → Sau khi gửi notification đầu tiên
    #   → Alertmanager gửi tiếp nếu có alert mới trong group
    #   → Nhưng tối thiểu 5 phút giữa 2 lần gửi
    groupInterval: 5m

    # repeatInterval: 12h
    #   → Nếu alert VẪN firing sau 12h
    #   → Alertmanager GỬI LẠI notification
    #   → Nhắc nhở team alert vẫn đang active
    repeatInterval: 12h

    # receiver: tên receiver để gửi notification
    receiver: email-receiver

    # matchers: điều kiện LỌC alerts
    #           Alert chỉ được route đến receiver này nếu MATCH matchers
    matchers:
      # name: tên label
      # value: giá trị label
      # matchType: = | != | =~ | !~
      - name: service
        value: api
        matchType: "="              # Chỉ nhận alerts có label service=api

  # receivers: danh sách receivers (đích đến notification)
  receivers:
    - name: email-receiver          # Tên trùng với route.receiver ở trên
      emailConfigs:
        - to: 'haileab542@gmail.com'   # Email người nhận
          from: 'alertmanager@cluster.local'  # Email gửi (hiển thị in box)
          # smarthost: SMTP server + port
          # Gmail SMTP: smtp.gmail.com:587 (TLS/STARTTLS)
          smarthost: 'smtp.gmail.com:587'
          # authUsername: tài khoản SMTP (email)
          authUsername: 'demeter.web.design.22@gmail.com'
          # authPassword: đọc từ Kubernetes Secret
          #              key: password → trỏ đến field "password" trong secret
          authPassword:
            name: alertmanager-email-secret
            key: password
          requireTLS: true          # Bắt buộc dùng TLS khi gửi email

          # headers: custom HTTP headers cho email
          headers:
            - key: Subject
              # Template Go: {{ .GroupLabels.X }} → thay bằng giá trị label
              # toUpper: filter, viết hoa severity
              value: '🚨 [{{ .GroupLabels.severity | toUpper }}] {{ .GroupLabels.alertname }}'
              # VD kết quả: "[CRITICAL] APIHighErrorRate"

          # text: body của email
          text: |
            ⚠️ ALERT FIRED ⚠️

            Alert: {{ .GroupLabels.alertname }}
            Severity: {{ .GroupLabels.severity }}

            # {{ range .Alerts }} ... {{ end }}: Go template loop
            # Duyệt qua tất cả alerts trong group
            {{ range .Alerts }}
            ---
            Summary: {{ .Annotations.summary }}
            Description: {{ .Annotations.description }}
            Started at: {{ .StartsAt }}
            {{ end }}

            Dashboard: http://grafana/d/api-metrics
```

---

### 5.3. Phần 3 — SMTP Secret (Hướng dẫn, không apply)

```yaml
# Secret: Kubernetes object lưu trữ dữ liệu NHẠY CẢM
#   → Password, token, API key, certificate, ...
#   → Không bao giờ commit vào Git!
#   → Tạo bằng kubectl command, không phải YAML file

# Cách tạo Secret:
kubectl create secret generic alertmanager-email-secret \
  -n demo \
  --from-literal=password='xxxx xxxx xxxx xxxx'

# Cách tạo Gmail App Password:
# 1. https://myaccount.google.com/apppasswords
# 2. Tạo App Password (16 ký tự, không khoảng trắng)
# 3. Dùng password này trong kubectl create secret
```

---

## 6. Giải thích cú pháp `app/app.py`

```python
import os
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

# PrometheusMetrics(app)
#   → Khởi tạo exporter, tự động thêm route /metrics
#   → Tự expose các metrics mặc định của Flask
#   → Flask request lifecycle được wrap để đếm metrics
app = Flask(__name__)
PrometheusMetrics(app)

# os.getenv("VERSION", "v1")
#   → Đọc env var VERSION từ container spec
#   → Nếu không có → mặc định "v1"
#   → Dùng trong response để verify version đang chạy
VER = os.getenv("VERSION", "v1")

@app.get("/")
def index():
    # jsonify: Flask helper → trả JSON response
    #   Content-Type: application/json
    # VD: {"ok": true, "version": "v7"}
    return jsonify(ok=True, version=VER)

@app.get("/healthz")
def healthz():
    # Kubernetes readinessProbe gọi endpoint này
    # → Return 200 = pod sẵn sàng nhận traffic
    # → Return != 200 = Kubernetes không route traffic vào pod
    return "ok", 200

@app.get("/api/bug")
def bug():
    # Endpoint mô phỏng lỗi 500 Internal Server Error
    # → Dùng để test SLO alert (APIHighErrorRate)
    # → Khi gọi, Prometheus ghi nhận status=500 trong metrics
    # → success_rate giảm → alert fire
    return jsonify(error="simulated internal server error"), 500
```

**Metrics tự động được expose tại `/metrics`:**

| Metric | Type | Ý nghĩa |
|--------|------|---------|
| `flask_http_request_total` | Counter | Tổng số requests, label theo `status`, `method`, `endpoint` |
| `flask_http_request_duration_seconds` | Histogram | Phân phối latency theo endpoint |

---

## 7. Giải thích cú pháp `send_rapid_bug.py`

```python
#!/usr/bin/env python3
"""Rapid error traffic generator cho SLO alert testing."""

import urllib.request
import threading
import time
import sys

# TARGET: endpoint /api/bug trả về HTTP 500
# localhost:8888 → port-forward của kubectl
# → kubectl port-forward svc/api 8888:8080
TARGET = "http://localhost:8888/api/bug"

# WORKERS: số luồng gửi request song song
# sys.argv[1]: đọc từ command line argument
# VD: python send_rapid_bug.py 4 → WORKERS = 4
WORKERS = int(sys.argv[1]) if len(sys.argv) > 1 else 4

# STOP_FLAG: threading.Event dùng để signal tất cả workers dừng
STOP_FLAG = threading.Event()

def worker(wid):
    """Mỗi worker: gửi request liên tục đến TARGET."""
    count = 0
    while not STOP_FLAG.is_set():   # Chạy đến khi có signal dừng
        try:
            req = urllib.request.urlopen(TARGET, timeout=1)
            req.close()
        except:
            # Target trả 500 → urllib raise exception
            # → except bắt và bỏ qua
            # → Request vẫn được Prometheus ghi nhận (dù có lỗi)
            pass
        count += 1
        if count % 200 == 0:
            print(f"[Worker-{wid}] Sent: {count}", flush=True)
    print(f"[Worker-{wid}] Total: {count}", flush=True)

# Tạo và start N worker threads
threads = []
print(f"Starting {WORKERS} workers targeting {TARGET}")
for i in range(WORKERS):
    t = threading.Thread(target=worker, args=(i+1,))
    t.start()
    threads.append(t)
    print(f"[+] Worker {i+1} started")

# Ctrl+C để dừng
print("Traffic is flowing. Press Ctrl+C to stop.")
try:
    while True:
        time.sleep(10)
        print(f"[{time.strftime('%H:%M:%S')}] Still sending errors...", flush=True)
except KeyboardInterrupt:
    # KeyboardInterrupt: Ctrl+C
    # → Set STOP_FLAG → tất cả workers exit while loop
    # → Join all threads → đợi workers hoàn thành
    print("Stopping...")
    STOP_FLAG.set()
    for t in threads:
        t.join()
    print("Done.")
```

**Cách sử dụng:**

```bash
# Terminal 1: port-forward API service
kubectl port-forward -n demo svc/api 8888:8080

# Terminal 2: chạy script
python send_rapid_bug.py 4

# → Gửi ~4 concurrent requests liên tục
# → Tất cả trả 500 (HTTP 500)
# → Prometheus scrape metrics → error_rate = 100%
# → APIHighErrorRate fire sau ~30s
```

---

## Bảng tổng hợp tất cả Custom Resource Definitions (CRD)

| Resource | CRD | Ai tạo ra CRD | File |
|----------|-----|---------------|------|
| `Rollout` | `argoproj.io/v1alpha1` | Argo Rollouts | `api.yaml` |
| `AnalysisTemplate` | `argoproj.io/v1alpha1` | Argo Rollouts | `analysis-template.yaml` |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Prometheus Operator | `api.yaml` |
| `PrometheusRule` | `monitoring.coreos.com/v1` | Prometheus Operator | `slo-alert.yaml` |
| `AlertmanagerConfig` | `monitoring.coreos.com/v1alpha1` | Prometheus Operator | `slo-alert.yaml` |
| `Service` | `v1` | Kubernetes (built-in) | `api.yaml` |

---

## 8. GitOps Dashboard (Backend + Frontend)

### 8.1. Tổng quan

Dashboard cho phép tương tác với hệ thống GitOps qua giao diện web thay vì CLI.

### 8.2. Cấu trúc thư mục

| Thư mục | File | Mô tả |
|----------|------|--------|
| `backend/` | `app.py` | Flask API — giao tiếp K8s + Prometheus |
| `backend/` | `requirements.txt` | flask, requests |
| `backend/` | `Dockerfile` | Build image |
| `fe/` | `index.html` | Dashboard UI (single-file HTML) |
| `k8s-dashboard/` | `manifests.yaml` | Namespace + Deployment + Service + RBAC |
| `argocd/apps/` | `dashboard.yaml` | ArgoCD Application |

### 8.3. API Endpoints

| Method | Path | Mô tả |
|--------|------|--------|
| GET | `/api/status` | Tổng hợp: Rollout phase, success rate, error rate, P95, alerts |
| GET | `/api/metrics/history?minutes=30` | Lịch sử metrics theo thời gian |
| POST | `/api/error/inject` | Bật error injection (body: `{"rate": 0.3}`) |
| POST | `/api/error/stop` | Tắt error injection |
| GET | `/api/error/inject` | Kiểm tra trạng thái error injection |

### 8.4. Chạy local

```bash
cd backend
pip install -r requirements.txt
python app.py
# Mở fe/index.html trong trình duyệt
```

### 8.5. Deploy lên K8s (qua ArgoCD)

```bash
docker build -t <registry>/dashboard-api:latest -f backend/Dockerfile .
docker push <registry>/dashboard-api:latest
# ArgoCD tự sync dashboard app → namespace dashboard
```

### 8.6. RBAC

Dashboard cần quyền đọc Rollouts + PrometheusRules:

```yaml
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts/status"]
    verbs: ["get", "list"]
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["prometheusrules"]
    verbs: ["get", "list"]
```

---

## 9. Debugging Guide — Alert email không hoạt động

### Kiểm tra từng bước

```bash
# 1. Prometheus scrape đúng metrics?
kubectl exec -n demo deploy/api -- curl -s http://localhost:8080/metrics | grep flask_http_request_total

# 2. Prometheus query có trả kết quả?
# Prometheus UI: sum(rate(flask_http_request_total{app="api"}[5m]))

# 3. PrometheusRule đúng?
kubectl get prometheusrule api-slo-alerts -n demo -o yaml

# 4. Alert đang firing?
kubectl get alertmanagerconfig api-email-alerts -n demo

# 5. Alertmanager log
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50

# 6. Kiểm tra secret tồn tại
kubectl get secret alertmanager-email-secret -n demo
```
