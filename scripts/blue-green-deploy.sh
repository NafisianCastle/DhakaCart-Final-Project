#!/bin/bash

# Blue-Green Deployment Script for DhakaCart
# This script implements zero-downtime deployments using Kubernetes

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-dhakacart}"
APP_NAME="${APP_NAME:-dhakacart}"
FRONTEND_IMAGE="${FRONTEND_IMAGE}"
BACKEND_IMAGE="${BACKEND_IMAGE}"
TIMEOUT="${TIMEOUT:-600}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if kubectl is available and configured
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not configured or cluster is not accessible"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to determine current active environment (blue or green)
get_current_environment() {
    local current_env
    current_env=$(kubectl get service "${APP_NAME}-service" -n "$NAMESPACE" -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "")
    
    if [[ "$current_env" == "blue" ]]; then
        echo "blue"
    elif [[ "$current_env" == "green" ]]; then
        echo "green"
    else
        # If no current environment is set, default to blue
        echo "blue"
    fi
}

# Function to get the target environment (opposite of current)
get_target_environment() {
    local current_env="$1"
    if [[ "$current_env" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Function to create deployment manifests for target environment
create_deployment_manifests() {
    local target_env="$1"
    local temp_dir="$2"
    
    log_info "Creating deployment manifests for $target_env environment..."
    
    # Frontend deployment
    cat > "$temp_dir/frontend-deployment-$target_env.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}-frontend-${target_env}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}-frontend
    version: ${target_env}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ${APP_NAME}-frontend
      version: ${target_env}
  template:
    metadata:
      labels:
        app: ${APP_NAME}-frontend
        version: ${target_env}
    spec:
      containers:
      - name: frontend
        image: ${FRONTEND_IMAGE}
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "0.1"
          limits:
            memory: "256Mi"
            cpu: "0.2"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        env:
        - name: REACT_APP_API_URL
          value: "/api"
        - name: REACT_APP_VERSION
          value: "${target_env}"
EOF

    # Backend deployment
    cat > "$temp_dir/backend-deployment-$target_env.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}-backend-${target_env}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}-backend
    version: ${target_env}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ${APP_NAME}-backend
      version: ${target_env}
  template:
    metadata:
      labels:
        app: ${APP_NAME}-backend
        version: ${target_env}
    spec:
      containers:
      - name: backend
        image: ${BACKEND_IMAGE}
        ports:
        - containerPort: 5000
        resources:
          requests:
            memory: "256Mi"
            cpu: "0.2"
          limits:
            memory: "512Mi"
            cpu: "0.5"
        livenessProbe:
          httpGet:
            path: /live
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        env:
        - name: NODE_ENV
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: ${APP_NAME}-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: ${APP_NAME}-secrets
              key: redis-url
        - name: VERSION
          value: "${target_env}"
EOF

    log_success "Deployment manifests created for $target_env environment"
}

# Function to deploy to target environment
deploy_to_target() {
    local target_env="$1"
    local temp_dir="$2"
    
    log_info "Deploying to $target_env environment..."
    
    # Apply deployments
    kubectl apply -f "$temp_dir/frontend-deployment-$target_env.yaml"
    kubectl apply -f "$temp_dir/backend-deployment-$target_env.yaml"
    
    # Wait for deployments to be ready
    log_info "Waiting for frontend deployment to be ready..."
    kubectl rollout status deployment/"${APP_NAME}-frontend-${target_env}" -n "$NAMESPACE" --timeout="${TIMEOUT}s"
    
    log_info "Waiting for backend deployment to be ready..."
    kubectl rollout status deployment/"${APP_NAME}-backend-${target_env}" -n "$NAMESPACE" --timeout="${TIMEOUT}s"
    
    log_success "Deployment to $target_env environment completed"
}

# Function to perform health checks on target environment
health_check_target() {
    local target_env="$1"
    
    log_info "Performing health checks on $target_env environment..."
    
    # Get pod IPs for direct health checks
    local frontend_pods
    local backend_pods
    
    frontend_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=${APP_NAME}-frontend,version=${target_env}" -o jsonpath='{.items[*].status.podIP}')
    backend_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=${APP_NAME}-backend,version=${target_env}" -o jsonpath='{.items[*].status.podIP}')
    
    # Health check backend pods
    for pod_ip in $backend_pods; do
        local retries=0
        while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
            if kubectl run health-check-backend-"$target_env"-"$retries" --rm -i --restart=Never --image=curlimages/curl -- \
                curl -f "http://$pod_ip:5000/health" --max-time 10 &> /dev/null; then
                log_success "Backend pod $pod_ip health check passed"
                kubectl delete pod health-check-backend-"$target_env"-"$retries" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
                break
            else
                retries=$((retries + 1))
                log_warning "Backend pod $pod_ip health check failed (attempt $retries/$HEALTH_CHECK_RETRIES)"
                kubectl delete pod health-check-backend-"$target_env"-"$retries" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
                if [[ $retries -eq $HEALTH_CHECK_RETRIES ]]; then
                    log_error "Backend pod $pod_ip health check failed after $HEALTH_CHECK_RETRIES attempts"
                    return 1
                fi
                sleep "$HEALTH_CHECK_INTERVAL"
            fi
        done
    done
    
    # Health check frontend pods
    for pod_ip in $frontend_pods; do
        local retries=0
        while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
            if kubectl run health-check-frontend-"$target_env"-"$retries" --rm -i --restart=Never --image=curlimages/curl -- \
                curl -f "http://$pod_ip:8080/health" --max-time 10 &> /dev/null; then
                log_success "Frontend pod $pod_ip health check passed"
                kubectl delete pod health-check-frontend-"$target_env"-"$retries" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
                break
            else
                retries=$((retries + 1))
                log_warning "Frontend pod $pod_ip health check failed (attempt $retries/$HEALTH_CHECK_RETRIES)"
                kubectl delete pod health-check-frontend-"$target_env"-"$retries" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
                if [[ $retries -eq $HEALTH_CHECK_RETRIES ]]; then
                    log_error "Frontend pod $pod_ip health check failed after $HEALTH_CHECK_RETRIES attempts"
                    return 1
                fi
                sleep "$HEALTH_CHECK_INTERVAL"
            fi
        done
    done
    
    log_success "All health checks passed for $target_env environment"
    return 0
}

# Function to switch traffic to target environment
switch_traffic() {
    local target_env="$1"
    
    log_info "Switching traffic to $target_env environment..."
    
    # Update service selectors to point to target environment
    kubectl patch service "${APP_NAME}-frontend-service" -n "$NAMESPACE" -p '{"spec":{"selector":{"version":"'$target_env'"}}}'
    kubectl patch service "${APP_NAME}-backend-service" -n "$NAMESPACE" -p '{"spec":{"selector":{"version":"'$target_env'"}}}'
    
    # Update main service selector
    kubectl patch service "${APP_NAME}-service" -n "$NAMESPACE" -p '{"spec":{"selector":{"version":"'$target_env'"}}}'
    
    log_success "Traffic switched to $target_env environment"
}

# Function to verify traffic switch
verify_traffic_switch() {
    local target_env="$1"
    
    log_info "Verifying traffic switch to $target_env environment..."
    
    # Get ingress URL
    local ingress_url
    ingress_url=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [[ -z "$ingress_url" ]]; then
        log_warning "Could not get ingress URL, using port-forward for verification"
        kubectl port-forward service/"${APP_NAME}-service" 8080:80 -n "$NAMESPACE" &
        local port_forward_pid=$!
        sleep 5
        ingress_url="localhost:8080"
    fi
    
    # Verify backend health through ingress
    local retries=0
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        if curl -f "http://$ingress_url/api/health" --max-time 10 &> /dev/null; then
            log_success "Traffic verification successful - backend responding through ingress"
            break
        else
            retries=$((retries + 1))
            log_warning "Traffic verification failed (attempt $retries/$HEALTH_CHECK_RETRIES)"
            if [[ $retries -eq $HEALTH_CHECK_RETRIES ]]; then
                log_error "Traffic verification failed after $HEALTH_CHECK_RETRIES attempts"
                if [[ -n "${port_forward_pid:-}" ]]; then
                    kill "$port_forward_pid" &> /dev/null || true
                fi
                return 1
            fi
            sleep "$HEALTH_CHECK_INTERVAL"
        fi
    done
    
    if [[ -n "${port_forward_pid:-}" ]]; then
        kill "$port_forward_pid" &> /dev/null || true
    fi
    
    log_success "Traffic switch verification completed"
    return 0
}

# Function to cleanup old environment
cleanup_old_environment() {
    local old_env="$1"
    
    log_info "Cleaning up $old_env environment..."
    
    # Delete old deployments
    kubectl delete deployment "${APP_NAME}-frontend-${old_env}" -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete deployment "${APP_NAME}-backend-${old_env}" -n "$NAMESPACE" --ignore-not-found=true
    
    log_success "Cleanup of $old_env environment completed"
}

# Function to rollback to previous environment
rollback() {
    local current_env="$1"
    local previous_env="$2"
    
    log_warning "Initiating rollback from $current_env to $previous_env..."
    
    # Check if previous environment deployments exist
    if kubectl get deployment "${APP_NAME}-frontend-${previous_env}" -n "$NAMESPACE" &> /dev/null && \
       kubectl get deployment "${APP_NAME}-backend-${previous_env}" -n "$NAMESPACE" &> /dev/null; then
        
        log_info "Previous environment deployments found, switching traffic back..."
        switch_traffic "$previous_env"
        
        if verify_traffic_switch "$previous_env"; then
            log_success "Rollback completed successfully"
            cleanup_old_environment "$current_env"
            return 0
        else
            log_error "Rollback verification failed"
            return 1
        fi
    else
        log_error "Previous environment deployments not found, cannot rollback"
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting blue-green deployment for DhakaCart..."
    
    # Validate required environment variables
    if [[ -z "${FRONTEND_IMAGE:-}" ]] || [[ -z "${BACKEND_IMAGE:-}" ]]; then
        log_error "FRONTEND_IMAGE and BACKEND_IMAGE environment variables are required"
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Create temporary directory for manifests
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Determine current and target environments
    local current_env
    local target_env
    current_env=$(get_current_environment)
    target_env=$(get_target_environment "$current_env")
    
    log_info "Current environment: $current_env"
    log_info "Target environment: $target_env"
    log_info "Frontend image: $FRONTEND_IMAGE"
    log_info "Backend image: $BACKEND_IMAGE"
    
    # Create and deploy to target environment
    create_deployment_manifests "$target_env" "$temp_dir"
    deploy_to_target "$target_env" "$temp_dir"
    
    # Perform health checks
    if ! health_check_target "$target_env"; then
        log_error "Health checks failed for $target_env environment"
        log_info "Cleaning up failed deployment..."
        cleanup_old_environment "$target_env"
        exit 1
    fi
    
    # Switch traffic to target environment
    switch_traffic "$target_env"
    
    # Verify traffic switch
    if ! verify_traffic_switch "$target_env"; then
        log_error "Traffic switch verification failed"
        log_info "Attempting rollback..."
        if rollback "$target_env" "$current_env"; then
            log_success "Rollback completed"
        else
            log_error "Rollback failed - manual intervention required"
        fi
        exit 1
    fi
    
    # Wait a bit to ensure stability
    log_info "Waiting for deployment to stabilize..."
    sleep 30
    
    # Final verification
    if verify_traffic_switch "$target_env"; then
        log_success "Deployment stabilized successfully"
        
        # Cleanup old environment
        cleanup_old_environment "$current_env"
        
        log_success "Blue-green deployment completed successfully!"
        log_info "Active environment: $target_env"
    else
        log_error "Final verification failed"
        log_info "Attempting rollback..."
        if rollback "$target_env" "$current_env"; then
            log_success "Rollback completed"
        else
            log_error "Rollback failed - manual intervention required"
        fi
        exit 1
    fi
}

# Run main function
main "$@"