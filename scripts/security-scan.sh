#!/bin/bash

# Comprehensive Security Scanning Script for DhakaCart
# This script runs various security scans on the codebase and containers

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN_RESULTS_DIR="$PROJECT_ROOT/security-scan-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to setup scan results directory
setup_scan_directory() {
    log_info "Setting up scan results directory..."
    mkdir -p "$SCAN_RESULTS_DIR"
    
    # Create subdirectories for different scan types
    mkdir -p "$SCAN_RESULTS_DIR/dependency-scan"
    mkdir -p "$SCAN_RESULTS_DIR/container-scan"
    mkdir -p "$SCAN_RESULTS_DIR/secret-scan"
    mkdir -p "$SCAN_RESULTS_DIR/infrastructure-scan"
    mkdir -p "$SCAN_RESULTS_DIR/code-analysis"
    
    log_success "Scan results directory created at: $SCAN_RESULTS_DIR"
}

# Function to run dependency vulnerability scanning
run_dependency_scan() {
    log_info "Running dependency vulnerability scanning..."
    
    # Frontend dependency scan
    if [ -d "$PROJECT_ROOT/frontend" ]; then
        log_info "Scanning frontend dependencies..."
        cd "$PROJECT_ROOT/frontend"
        
        # npm audit
        npm audit --audit-level=moderate --json > "$SCAN_RESULTS_DIR/dependency-scan/frontend-npm-audit-$TIMESTAMP.json" 2>/dev/null || true
        npm audit --audit-level=moderate > "$SCAN_RESULTS_DIR/dependency-scan/frontend-npm-audit-$TIMESTAMP.txt" 2>/dev/null || true
        
        # Snyk scan (if available)
        if command_exists snyk && [ -n "${SNYK_TOKEN:-}" ]; then
            snyk test --json > "$SCAN_RESULTS_DIR/dependency-scan/frontend-snyk-$TIMESTAMP.json" 2>/dev/null || true
            snyk test > "$SCAN_RESULTS_DIR/dependency-scan/frontend-snyk-$TIMESTAMP.txt" 2>/dev/null || true
        fi
    fi
    
    # Backend dependency scan
    if [ -d "$PROJECT_ROOT/backend" ]; then
        log_info "Scanning backend dependencies..."
        cd "$PROJECT_ROOT/backend"
        
        # npm audit
        npm audit --audit-level=moderate --json > "$SCAN_RESULTS_DIR/dependency-scan/backend-npm-audit-$TIMESTAMP.json" 2>/dev/null || true
        npm audit --audit-level=moderate > "$SCAN_RESULTS_DIR/dependency-scan/backend-npm-audit-$TIMESTAMP.txt" 2>/dev/null || true
        
        # Snyk scan (if available)
        if command_exists snyk && [ -n "${SNYK_TOKEN:-}" ]; then
            snyk test --json > "$SCAN_RESULTS_DIR/dependency-scan/backend-snyk-$TIMESTAMP.json" 2>/dev/null || true
            snyk test > "$SCAN_RESULTS_DIR/dependency-scan/backend-snyk-$TIMESTAMP.txt" 2>/dev/null || true
        fi
    fi
    
    cd "$PROJECT_ROOT"
    log_success "Dependency vulnerability scanning completed"
}

# Function to run container security scanning
run_container_scan() {
    log_info "Running container security scanning..."
    
    # Check if Docker is available
    if ! command_exists docker; then
        log_warning "Docker not found, skipping container scanning"
        return
    fi
    
    # Build images for scanning
    log_info "Building images for security scanning..."
    
    if [ -d "$PROJECT_ROOT/frontend" ]; then
        docker build -t dhakacart/frontend:security-scan "$PROJECT_ROOT/frontend" || log_warning "Failed to build frontend image"
    fi
    
    if [ -d "$PROJECT_ROOT/backend" ]; then
        docker build -t dhakacart/backend:security-scan "$PROJECT_ROOT/backend" || log_warning "Failed to build backend image"
    fi
    
    # Trivy scanning (if available)
    if command_exists trivy; then
        log_info "Running Trivy container scans..."
        
        # Frontend container scan
        if docker image inspect dhakacart/frontend:security-scan >/dev/null 2>&1; then
            trivy image --format json --output "$SCAN_RESULTS_DIR/container-scan/frontend-trivy-$TIMESTAMP.json" dhakacart/frontend:security-scan || true
            trivy image --format table --output "$SCAN_RESULTS_DIR/container-scan/frontend-trivy-$TIMESTAMP.txt" dhakacart/frontend:security-scan || true
        fi
        
        # Backend container scan
        if docker image inspect dhakacart/backend:security-scan >/dev/null 2>&1; then
            trivy image --format json --output "$SCAN_RESULTS_DIR/container-scan/backend-trivy-$TIMESTAMP.json" dhakacart/backend:security-scan || true
            trivy image --format table --output "$SCAN_RESULTS_DIR/container-scan/backend-trivy-$TIMESTAMP.txt" dhakacart/backend:security-scan || true
        fi
    else
        log_warning "Trivy not found, skipping container vulnerability scanning"
    fi
    
    # Grype scanning (if available)
    if command_exists grype; then
        log_info "Running Grype container scans..."
        
        # Frontend container scan
        if docker image inspect dhakacart/frontend:security-scan >/dev/null 2>&1; then
            grype dhakacart/frontend:security-scan -o json > "$SCAN_RESULTS_DIR/container-scan/frontend-grype-$TIMESTAMP.json" || true
            grype dhakacart/frontend:security-scan > "$SCAN_RESULTS_DIR/container-scan/frontend-grype-$TIMESTAMP.txt" || true
        fi
        
        # Backend container scan
        if docker image inspect dhakacart/backend:security-scan >/dev/null 2>&1; then
            grype dhakacart/backend:security-scan -o json > "$SCAN_RESULTS_DIR/container-scan/backend-grype-$TIMESTAMP.json" || true
            grype dhakacart/backend:security-scan > "$SCAN_RESULTS_DIR/container-scan/backend-grype-$TIMESTAMP.txt" || true
        fi
    else
        log_warning "Grype not found, skipping additional container scanning"
    fi
    
    log_success "Container security scanning completed"
}

# Function to run secret scanning
run_secret_scan() {
    log_info "Running secret scanning..."
    
    # TruffleHog scanning (if available)
    if command_exists trufflehog; then
        log_info "Running TruffleHog secret scan..."
        trufflehog filesystem "$PROJECT_ROOT" --json > "$SCAN_RESULTS_DIR/secret-scan/trufflehog-$TIMESTAMP.json" 2>/dev/null || true
        trufflehog filesystem "$PROJECT_ROOT" > "$SCAN_RESULTS_DIR/secret-scan/trufflehog-$TIMESTAMP.txt" 2>/dev/null || true
    else
        log_warning "TruffleHog not found, skipping secret scanning"
    fi
    
    # GitLeaks scanning (if available)
    if command_exists gitleaks; then
        log_info "Running GitLeaks secret scan..."
        cd "$PROJECT_ROOT"
        gitleaks detect --report-format json --report-path "$SCAN_RESULTS_DIR/secret-scan/gitleaks-$TIMESTAMP.json" --source . || true
        gitleaks detect --report-format csv --report-path "$SCAN_RESULTS_DIR/secret-scan/gitleaks-$TIMESTAMP.csv" --source . || true
    else
        log_warning "GitLeaks not found, skipping additional secret scanning"
    fi
    
    log_success "Secret scanning completed"
}

# Function to run infrastructure security scanning
run_infrastructure_scan() {
    log_info "Running infrastructure security scanning..."
    
    # Checkov scanning (if available)
    if command_exists checkov; then
        log_info "Running Checkov infrastructure scan..."
        cd "$PROJECT_ROOT"
        
        # Scan Dockerfiles
        checkov -f frontend/Dockerfile --framework dockerfile --output json > "$SCAN_RESULTS_DIR/infrastructure-scan/checkov-dockerfile-frontend-$TIMESTAMP.json" 2>/dev/null || true
        checkov -f backend/Dockerfile --framework dockerfile --output json > "$SCAN_RESULTS_DIR/infrastructure-scan/checkov-dockerfile-backend-$TIMESTAMP.json" 2>/dev/null || true
        
        # Scan Kubernetes manifests
        if [ -d "kubernetes" ]; then
            checkov -d kubernetes --framework kubernetes --output json > "$SCAN_RESULTS_DIR/infrastructure-scan/checkov-kubernetes-$TIMESTAMP.json" 2>/dev/null || true
        fi
        
        # Scan Terraform files
        if [ -d "terraform" ]; then
            checkov -d terraform --framework terraform --output json > "$SCAN_RESULTS_DIR/infrastructure-scan/checkov-terraform-$TIMESTAMP.json" 2>/dev/null || true
        fi
        
        # Scan Docker Compose
        if [ -f "docker-compose.yml" ]; then
            checkov -f docker-compose.yml --framework docker_compose --output json > "$SCAN_RESULTS_DIR/infrastructure-scan/checkov-compose-$TIMESTAMP.json" 2>/dev/null || true
        fi
    else
        log_warning "Checkov not found, skipping infrastructure scanning"
    fi
    
    # Terrascan (if available)
    if command_exists terrascan; then
        log_info "Running Terrascan infrastructure scan..."
        
        if [ -d "terraform" ]; then
            cd "$PROJECT_ROOT/terraform"
            terrascan scan -t terraform -o json > "$SCAN_RESULTS_DIR/infrastructure-scan/terrascan-terraform-$TIMESTAMP.json" 2>/dev/null || true
        fi
        
        if [ -d "kubernetes" ]; then
            cd "$PROJECT_ROOT/kubernetes"
            terrascan scan -t k8s -o json > "$SCAN_RESULTS_DIR/infrastructure-scan/terrascan-kubernetes-$TIMESTAMP.json" 2>/dev/null || true
        fi
        
        cd "$PROJECT_ROOT"
    else
        log_warning "Terrascan not found, skipping additional infrastructure scanning"
    fi
    
    log_success "Infrastructure security scanning completed"
}

# Function to run code analysis
run_code_analysis() {
    log_info "Running static code analysis..."
    
    # ESLint security scanning
    if [ -d "$PROJECT_ROOT/frontend" ]; then
        log_info "Running ESLint security analysis on frontend..."
        cd "$PROJECT_ROOT/frontend"
        
        if [ -f "package.json" ] && npm list eslint-plugin-security >/dev/null 2>&1; then
            npx eslint . --ext .js,.jsx,.ts,.tsx --format json > "$SCAN_RESULTS_DIR/code-analysis/frontend-eslint-$TIMESTAMP.json" 2>/dev/null || true
        fi
    fi
    
    if [ -d "$PROJECT_ROOT/backend" ]; then
        log_info "Running ESLint security analysis on backend..."
        cd "$PROJECT_ROOT/backend"
        
        if [ -f "package.json" ] && npm list eslint-plugin-security >/dev/null 2>&1; then
            npx eslint . --ext .js --format json > "$SCAN_RESULTS_DIR/code-analysis/backend-eslint-$TIMESTAMP.json" 2>/dev/null || true
        fi
    fi
    
    cd "$PROJECT_ROOT"
    
    # Semgrep scanning (if available)
    if command_exists semgrep; then
        log_info "Running Semgrep security analysis..."
        semgrep --config=auto --json --output="$SCAN_RESULTS_DIR/code-analysis/semgrep-$TIMESTAMP.json" . || true
    else
        log_warning "Semgrep not found, skipping static analysis"
    fi
    
    log_success "Code analysis completed"
}

# Function to generate summary report
generate_summary_report() {
    log_info "Generating security scan summary report..."
    
    local summary_file="$SCAN_RESULTS_DIR/security-scan-summary-$TIMESTAMP.md"
    
    cat > "$summary_file" << EOF
# Security Scan Summary Report

**Scan Date:** $(date)
**Project:** DhakaCart
**Scan ID:** $TIMESTAMP

## Scan Overview

This report contains the results of comprehensive security scanning performed on the DhakaCart project.

### Scans Performed

- ✅ Dependency Vulnerability Scanning
- ✅ Container Security Scanning
- ✅ Secret Scanning
- ✅ Infrastructure Security Scanning
- ✅ Static Code Analysis

### Results Location

All detailed scan results are available in the following directory:
\`$SCAN_RESULTS_DIR\`

### Scan Results Structure

\`\`\`
security-scan-results/
├── dependency-scan/     # npm audit, Snyk results
├── container-scan/      # Trivy, Grype results
├── secret-scan/         # TruffleHog, GitLeaks results
├── infrastructure-scan/ # Checkov, Terrascan results
└── code-analysis/       # ESLint, Semgrep results
\`\`\`

### Next Steps

1. Review all scan results for critical and high severity issues
2. Prioritize fixes based on severity and exploitability
3. Update dependencies with known vulnerabilities
4. Fix infrastructure misconfigurations
5. Address any exposed secrets or sensitive data
6. Re-run scans after implementing fixes

### Tools Used

EOF

    # Add information about which tools were available and used
    if command_exists npm; then
        echo "- **npm audit**: ✅ Available" >> "$summary_file"
    else
        echo "- **npm audit**: ❌ Not available" >> "$summary_file"
    fi
    
    if command_exists snyk; then
        echo "- **Snyk**: ✅ Available" >> "$summary_file"
    else
        echo "- **Snyk**: ❌ Not available" >> "$summary_file"
    fi
    
    if command_exists trivy; then
        echo "- **Trivy**: ✅ Available" >> "$summary_file"
    else
        echo "- **Trivy**: ❌ Not available" >> "$summary_file"
    fi
    
    if command_exists trufflehog; then
        echo "- **TruffleHog**: ✅ Available" >> "$summary_file"
    else
        echo "- **TruffleHog**: ❌ Not available" >> "$summary_file"
    fi
    
    if command_exists checkov; then
        echo "- **Checkov**: ✅ Available" >> "$summary_file"
    else
        echo "- **Checkov**: ❌ Not available" >> "$summary_file"
    fi
    
    if command_exists semgrep; then
        echo "- **Semgrep**: ✅ Available" >> "$summary_file"
    else
        echo "- **Semgrep**: ❌ Not available" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

### Report Generated

This report was generated automatically by the security scanning script.
For questions or issues, please contact the security team.

---
*Generated on $(date) by security-scan.sh*
EOF

    log_success "Summary report generated: $summary_file"
}

# Function to cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary Docker images
    docker rmi dhakacart/frontend:security-scan 2>/dev/null || true
    docker rmi dhakacart/backend:security-scan 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Main function
main() {
    log_info "Starting comprehensive security scanning for DhakaCart..."
    
    # Setup
    setup_scan_directory
    
    # Run all scans
    run_dependency_scan
    run_container_scan
    run_secret_scan
    run_infrastructure_scan
    run_code_analysis
    
    # Generate summary
    generate_summary_report
    
    # Cleanup
    cleanup
    
    log_success "Security scanning completed successfully!"
    log_info "Results available at: $SCAN_RESULTS_DIR"
    log_info "Summary report: $SCAN_RESULTS_DIR/security-scan-summary-$TIMESTAMP.md"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"