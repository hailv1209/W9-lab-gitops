#!/bin/bash
# Script test canary deployment - Auto promote vs Auto abort

set -e

echo "🚀 CANARY DEPLOYMENT TEST SCRIPT"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Config
NAMESPACE="demo"
ROLLOUT_NAME="api"
API_FILE="k8s-api/api.yaml"

# Kiểm tra prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    
    # Check argo rollouts plugin
    if ! kubectl argo rollouts version &> /dev/null; then
        echo -e "${RED}❌ kubectl argo rollouts plugin not installed${NC}"
        echo "Install: curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64"
        exit 1
    fi
    
    # Check namespace
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        echo -e "${RED}❌ Namespace $NAMESPACE not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Prerequisites OK${NC}"
    echo ""
}

# Hiển thị trạng thái hiện tại
show_current_status() {
    echo "📊 Current Rollout Status:"
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE
    echo ""
}

# Generate traffic để có metrics
generate_traffic() {
    echo "🌐 Generating traffic to API..."
    echo "   (Cần để có metrics cho AnalysisTemplate)"
    
    # Get API service URL
    API_URL=$(kubectl get svc $ROLLOUT_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}'):8080
    
    echo "   Target: http://$API_URL/"
    echo "   Duration: 5 minutes (background process)"
    
    # Run traffic generator in background
    (
        for i in {1..300}; do
            curl -s http://$API_URL/ > /dev/null || true
            sleep 1
        done
    ) &
    
    TRAFFIC_PID=$!
    echo "   Traffic generator PID: $TRAFFIC_PID"
    echo ""
}

# Test Case 1: Deploy good version
test_good_version() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}TEST 1: Deploy GOOD Version (Auto-Promote)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "📝 Preparing good version (ERROR_RATE=0)..."
    
    # Backup current file
    cp $API_FILE ${API_FILE}.backup
    
    # Update to good version
    sed -i 's/value: ".*" # ERROR_RATE/value: "0" # ERROR_RATE/' $API_FILE
    sed -i 's/value: "v.*"/value: "v1-good"/' $API_FILE
    sed -i 's/image: w9-api:.*/image: w9-api:good/' $API_FILE
    
    echo "✓ Updated $API_FILE:"
    echo "  - ERROR_RATE: 0 (no errors)"
    echo "  - VERSION: v1-good"
    echo "  - IMAGE: w9-api:good"
    echo ""
    
    read -p "Press Enter to commit and push..."
    
    # Git commit & push
    git add $API_FILE
    git commit -m "test: deploy good version (expect auto-promote)"
    git push
    
    echo ""
    echo "⏳ Waiting for ArgoCD to sync (30s)..."
    sleep 30
    
    echo ""
    echo "👀 Watching rollout (Ctrl+C to stop)..."
    echo "   Expected: Auto-promote to 100%"
    echo ""
    
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE --watch
}

# Test Case 2: Deploy bad version
test_bad_version() {
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}TEST 2: Deploy BAD Version (Auto-Abort)${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "📝 Preparing bad version (ERROR_RATE=0.5)..."
    
    # Update to bad version
    sed -i 's/value: ".*" # ERROR_RATE/value: "0.5" # ERROR_RATE/' $API_FILE
    sed -i 's/value: "v.*"/value: "v2-bad"/' $API_FILE
    sed -i 's/image: w9-api:.*/image: w9-api:bad/' $API_FILE
    
    echo "✓ Updated $API_FILE:"
    echo "  - ERROR_RATE: 0.5 (50% errors)"
    echo "  - VERSION: v2-bad"
    echo "  - IMAGE: w9-api:bad"
    echo ""
    
    read -p "Press Enter to commit and push..."
    
    # Git commit & push
    git add $API_FILE
    git commit -m "test: deploy bad version (expect auto-abort)"
    git push
    
    echo ""
    echo "⏳ Waiting for ArgoCD to sync (30s)..."
    sleep 30
    
    echo ""
    echo "👀 Watching rollout (Ctrl+C to stop)..."
    echo "   Expected: Auto-abort and rollback"
    echo ""
    
    kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE --watch
}

# Test Case 3: Git revert rollback
test_git_rollback() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}TEST 3: Git Revert Rollback (<5 minutes)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "📊 Current git log:"
    git log --oneline -5
    echo ""
    
    echo "⏰ Starting timer..."
    START_TIME=$(date +%s)
    
    read -p "Press Enter to revert last commit..."
    
    # Git revert
    git revert HEAD --no-edit
    git push
    
    echo ""
    echo "⏳ Waiting for ArgoCD to sync and rollout to complete..."
    
    # Wait for sync
    sleep 30
    
    # Wait for rollout to be healthy
    kubectl argo rollouts status $ROLLOUT_NAME -n $NAMESPACE
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo -e "${GREEN}✓ Rollback completed!${NC}"
    echo "⏱️  Total time: ${DURATION} seconds (< 5 minutes = 300s)"
    
    if [ $DURATION -lt 300 ]; then
        echo -e "${GREEN}✓ PASS: Rollback time < 5 minutes${NC}"
    else
        echo -e "${RED}✗ FAIL: Rollback time >= 5 minutes${NC}"
    fi
    
    echo ""
    show_current_status
}

# Xem AnalysisRun details
show_analysis_runs() {
    echo "🔍 Recent AnalysisRuns:"
    kubectl get analysisrun -n $NAMESPACE -l rollout=$ROLLOUT_NAME --sort-by=.metadata.creationTimestamp
    echo ""
    
    echo "📊 Latest AnalysisRun details:"
    LATEST_AR=$(kubectl get analysisrun -n $NAMESPACE -l rollout=$ROLLOUT_NAME --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
    
    if [ -n "$LATEST_AR" ]; then
        kubectl describe analysisrun $LATEST_AR -n $NAMESPACE | grep -A 20 "Status:"
    else
        echo "No AnalysisRuns found yet"
    fi
    echo ""
}

# Main menu
show_menu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "          CANARY TEST MENU"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Test Good Version (Auto-Promote)"
    echo "2. Test Bad Version (Auto-Abort)"
    echo "3. Test Git Rollback (<5min)"
    echo "4. Show Current Status"
    echo "5. Show AnalysisRuns"
    echo "6. Generate Traffic"
    echo "7. Run All Tests (Full Demo)"
    echo "0. Exit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Run all tests
run_all_tests() {
    echo "🎬 Running full demo sequence..."
    echo ""
    
    generate_traffic
    sleep 5
    
    test_good_version
    
    echo ""
    read -p "Test 1 completed. Press Enter to continue to Test 2..."
    
    test_bad_version
    
    echo ""
    read -p "Test 2 completed. Press Enter to continue to Test 3..."
    
    test_git_rollback
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ALL TESTS COMPLETED!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    show_analysis_runs
}

# Main
main() {
    check_prerequisites
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1) test_good_version ;;
            2) test_bad_version ;;
            3) test_git_rollback ;;
            4) show_current_status ;;
            5) show_analysis_runs ;;
            6) generate_traffic ;;
            7) run_all_tests ;;
            0) 
                echo "👋 Bye!"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# Run
main
