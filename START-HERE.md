# HƯỚNG DẪN KHỞI CHẠY — W9 GitOps Lab

## Cluster Kind (nếu chưa có cluster)

```powershell
# 1. Tạo cluster Kind
kind create cluster --name gitops

# 2. Cài ArgoCD (không qua Git, apply trực tiếp)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Đợi ArgoCD ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

# 4. Lấy password ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 5. Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Mở trình duyệt: http://localhost:8080
# Username: admin
# Password: (lấy ở bước 4)
```

---

## Bước 1 — Cài ArgoCD (nếu chưa có)

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Đợi ready:

```powershell
kubectl get pods -n argocd
# Tất cả pod phải Running/Completed
```

---

## Bước 2 — Cài ArgoCD CLI (Windows)

```powershell
# Cách 1: winget
winget install ArgoCLI.Argo

# Cách 2: Chocolatey
choco install argocd-cli -y

# Cách 3: Download trực tiếp
# https://github.com/argoproj/argo-cd/releases/latest
# Download argocd-windows-amd64.exe → đổi tên thành argocd.exe → cho vào PATH
```

Kiểm tra:

```powershell
argocd version
```

---

## Bước 3 — Login ArgoCD CLI

```powershell
# Port-forward trước (mở terminal riêng, giữ chạy)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login (mở terminal mới)
argocd login localhost:8080 --username admin --password YOUR_PASSWORD
```

---

## Bước 4 — Apply Root App (GitOps bắt đầu từ đây)

```powershell
# Clone repo (nếu chưa có)
git clone https://github.com/hailv1209/W9-lab-gitops.git
cd W9-lab-gitops

# Apply root ArgoCD Application
kubectl apply -f argocd/root.yaml

# ArgoCD sẽ tự động discover tất cả app trong argocd/apps/
# Tự sync: argo-rollouts, kube-prometheus-stack, api, fe, be, web
```

Xem trạng thái:

```powershell
argocd app list
argocd app get root
```

---

## Bước 5 — Đợi Infrastructure sync

```powershell
# Kiểm tra từng app
argocd app get argo-rollouts
argocd app get kube-prometheus-stack
argocd app get api
argocd app get fe
argocd app get be
argocd app get web
```

Chờ tất cả `Synced` và `Healthy`:

```powershell
# Theo dõi liên tục
watch argocd app list
```

---

## Bước 6 — Argo Rollouts CLI (nếu cần)

```powershell
# winget
winget install ArgoCLI.ArgoRollouts

# Kiểm tra rollout
kubectl argo rollouts get rollout api -n demo -w
```

---

## Bước 7 — Prometheus UI

```powershell
# Prometheus (port-forward)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Mở: http://localhost:9090
```

---

## Bước 8 — Grafana

```powershell
# Grafana (port-forward)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Mở: http://localhost:3000
# Default: admin / prom-operator (hoặc xem secret)
```

Lấy password Grafana:

```powershell
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

---

## Bước 9 — ArgoCD UI

```powershell
# ArgoCD UI (port-forward)
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Mở: http://localhost:8080
# Username: admin
# Password: (xem bước 3)
```

---

## Bước 10 — Tạo SMTP Secret (Alert Email)

```powershell
# Tạo Gmail App Password:
#   1. https://myaccount.google.com/apppasswords
#   2. Tạo App Password cho "Mail" (16 ký tự)
#   3. Dùng password đó thay YOUR_APP_PASSWORD

kubectl create secret generic alertmanager-email-secret `
  -n demo `
  --from-literal=password='YOUR_APP_PASSWORD'

# Kiểm tra
kubectl get secret alertmanager-email-secret -n demo
```

---

## Bước 11 — Dashboard BE (GitOps Dashboard)

```powershell
# Build image (thay <registry> bằng registry của bạn)
docker build -t <registry>/dashboard-api:latest -f backend/Dockerfile .
docker push <registry>/dashboard-api:latest

# ArgoCD sẽ tự sync dashboard app
argocd app get dashboard

# Hoặc chạy local thay vì deploy lên K8s:
cd backend
pip install -r requirements.txt
python app.py

# Mở fe/index.html trong trình duyệt
```

---

## Bước 12 — Test Alert

```powershell
# Terminal 1: port-forward API
kubectl port-forward -n demo svc/api 8888:8080

# Terminal 2: gửi error traffic (cài Python trước)
python app/app.py
# Hoặc curl:
while($true) {
    try {
        Invoke-WebRequest -Uri "http://localhost:8888/api/bug" -UseBasicParsing -ErrorAction SilentlyContinue
        Write-Host "." -NoNewline
    } catch {}
    Start-Sleep -Milliseconds 200
}
```

---

## Các Lệnh Thường Dùng

```powershell
# Xem rollout
kubectl argo rollouts get rollout api -n demo -w

# Xem pods
kubectl get pods -n demo -w

# Xem logs
kubectl logs -n demo -l app=api --tail=50 -f

# Rollback
git revert HEAD --no-edit
git push

# ArgoCD sync tay
argocd app sync api
argocd app sync root

# Xem Prometheus alerts
kubectl get prometheusrule api-slo-alerts -n demo

# Xem Alertmanager config
kubectl get alertmanagerconfig api-email-alerts -n demo

# Alertmanager logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50 -f

# Prometheus query
# http://localhost:9090 → query:
# sum(rate(flask_http_request_total{app="api"}[5m]))
```

---

## Thứ tự Port-Forward (mở nhiều terminal)

| Terminal | Lệnh | Truy cập |
|----------|-------|-----------|
| 1 | `kubectl port-forward -n argocd svc/argocd-server 8080:443` | http://localhost:8080 |
| 2 | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | http://localhost:9090 |
| 3 | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` | http://localhost:3000 |
| 4 | `kubectl port-forward -n demo svc/api 8888:8080` | localhost:8888 |

---

## Xử lý lỗi thường gặp

```powershell
# ArgoCD app OutOfSync → sync tay
argocd app sync root --force

# Pod không start → xem logs
kubectl describe pod POD_NAME -n demo

# ArgoCD không thấy app mới → hard refresh
argocd app get root --refresh

# Helm chart lỗi → xem diff
argocd app diff kube-prometheus-stack
```
