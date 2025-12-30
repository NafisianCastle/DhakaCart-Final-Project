# Blue-Green Deployment Script for DhakaCart (PowerShell)
# This script implements zero-downtime deployments using Kubernetes

param(
    [Parameter(Mandatory=$true)]
    [string]$FrontendImage,
    
    [Parameter(Mandatory=$true)]
    [string]$BackendImage,
    
    [string]$Namespace = "dhakacart",
    [string]$AppName = "dhakacart",
    [int]$Timeout = 600,
    [int]$HealthCheckRetries = 30,
    [int]$HealthCheckInterval = 10
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Logging functions
function Write-InfoLog {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-SuccessLog {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-InfoLog "Checking prerequisites..."
    
    # Check if kubectl is available
    try {
        $null = kubectl version --client=true 2>$null
    }
    catch {
        Write-ErrorLog "kubectl is not installed or not in PATH"
        exit 1
    }
    
    # Check cluster connectivity
    try {
        $null = kubectl cluster-info 2>$null
    }
    catch {
        Write-ErrorLog "kubectl is not configured or cluster is not accessible"
        exit 1
    }
    
    # Check namespace exists
    try {
        $null = kubectl get namespace $Namespace 2>$null
    }
    catch {
        Write-ErrorLog "Namespace '$Namespace' does not exist"
        exit 1
    }
    
    Write-SuccessLog "Prerequisites check passed"
}

# Function to get current environment
function Get-CurrentEnvironment {
    try {
        $currentEnv = kubectl get service "$AppName-service" -n $Namespace -o jsonpath='{.spec.selector.version}' 2>$null
        if ([string]::IsNullOrEmpty($currentEnv)) {
            return "blue"
        }
        return $currentEnv
    }
    catch {
        return "blue"
    }
}

# Function to get target environment
function Get-TargetEnvironment {
    param([string]$CurrentEnv)
    
    if ($CurrentEnv -eq "blue") {
        return "green"
    }
    else {
        return "blue"
    }
}

# Function to create deployment manifests
function New-DeploymentManifests {
    param(
        [string]$TargetEnv,
        [string]$TempDir
    )
    
    Write-InfoLog "Creating deployment manifests for $TargetEnv environment..."
    
    # Frontend deployment manifest
    $frontendManifest = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $AppName-frontend-$TargetEnv
  namespace: $Namespace
  labels:
    app: $AppName-frontend
    version: $TargetEnv
spec:
  replicas: 3
  selector:
    matchLabels:
      app: $AppName-frontend
      version: $TargetEnv
  template:
    metadata:
      labels:
        app: $AppName-frontend
        version: $TargetEnv
    spec:
      containers:
      - name: frontend
        image: $FrontendImage
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
          value: "$TargetEnv"
"@

    # Backend deployment manifest
    $backendManifest = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $AppName-backend-$TargetEnv
  namespace: $Namespace
  labels:
    app: $AppName-backend
    version: $TargetEnv
spec:
  replicas: 3
  selector:
    matchLabels:
      app: $AppName-backend
      version: $TargetEnv
  template:
    metadata:
      labels:
        app: $AppName-backend
        version: $TargetEnv
    spec:
      containers:
      - name: backend
        image: $BackendImage
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
              name: $AppName-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: $AppName-secrets
              key: redis-url
        - name: VERSION
          value: "$TargetEnv"
"@

    # Save manifests to files
    $frontendManifest | Out-File -FilePath "$TempDir\frontend-deployment-$TargetEnv.yaml" -Encoding UTF8
    $backendManifest | Out-File -FilePath "$TempDir\backend-deployment-$TargetEnv.yaml" -Encoding UTF8
    
    Write-SuccessLog "Deployment manifests created for $TargetEnv environment"
}

# Function to deploy to target environment
function Deploy-ToTarget {
    param(
        [string]$TargetEnv,
        [string]$TempDir
    )
    
    Write-InfoLog "Deploying to $TargetEnv environment..."
    
    # Apply deployments
    kubectl apply -f "$TempDir\frontend-deployment-$TargetEnv.yaml"
    kubectl apply -f "$TempDir\backend-deployment-$TargetEnv.yaml"
    
    # Wait for deployments to be ready
    Write-InfoLog "Waiting for frontend deployment to be ready..."
    kubectl rollout status deployment/"$AppName-frontend-$TargetEnv" -n $Namespace --timeout="$($Timeout)s"
    
    Write-InfoLog "Waiting for backend deployment to be ready..."
    kubectl rollout status deployment/"$AppName-backend-$TargetEnv" -n $Namespace --timeout="$($Timeout)s"
    
    Write-SuccessLog "Deployment to $TargetEnv environment completed"
}

# Function to perform health checks
function Test-TargetHealth {
    param([string]$TargetEnv)
    
    Write-InfoLog "Performing health checks on $TargetEnv environment..."
    
    # Get pod IPs
    $frontendPods = kubectl get pods -n $Namespace -l "app=$AppName-frontend,version=$TargetEnv" -o jsonpath='{.items[*].status.podIP}'
    $backendPods = kubectl get pods -n $Namespace -l "app=$AppName-backend,version=$TargetEnv" -o jsonpath='{.items[*].status.podIP}'
    
    # Health check backend pods
    foreach ($podIp in $backendPods -split ' ') {
        if ([string]::IsNullOrEmpty($podIp)) { continue }
        
        $retries = 0
        $healthPassed = $false
        
        while ($retries -lt $HealthCheckRetries) {
            try {
                $checkName = "health-check-backend-$TargetEnv-$retries"
                kubectl run $checkName --rm -i --restart=Never --image=curlimages/curl -- curl -f "http://$podIp:5000/health" --max-time 10 2>$null
                Write-SuccessLog "Backend pod $podIp health check passed"
                $healthPassed = $true
                break
            }
            catch {
                $retries++
                Write-WarningLog "Backend pod $podIp health check failed (attempt $retries/$HealthCheckRetries)"
                kubectl delete pod $checkName -n $Namespace --ignore-not-found=true 2>$null
                if ($retries -eq $HealthCheckRetries) {
                    Write-ErrorLog "Backend pod $podIp health check failed after $HealthCheckRetries attempts"
                    return $false
                }
                Start-Sleep -Seconds $HealthCheckInterval
            }
        }
        
        if (-not $healthPassed) {
            return $false
        }
    }
    
    # Health check frontend pods
    foreach ($podIp in $frontendPods -split ' ') {
        if ([string]::IsNullOrEmpty($podIp)) { continue }
        
        $retries = 0
        $healthPassed = $false
        
        while ($retries -lt $HealthCheckRetries) {
            try {
                $checkName = "health-check-frontend-$TargetEnv-$retries"
                kubectl run $checkName --rm -i --restart=Never --image=curlimages/curl -- curl -f "http://$podIp:8080/health" --max-time 10 2>$null
                Write-SuccessLog "Frontend pod $podIp health check passed"
                $healthPassed = $true
                break
            }
            catch {
                $retries++
                Write-WarningLog "Frontend pod $podIp health check failed (attempt $retries/$HealthCheckRetries)"
                kubectl delete pod $checkName -n $Namespace --ignore-not-found=true 2>$null
                if ($retries -eq $HealthCheckRetries) {
                    Write-ErrorLog "Frontend pod $podIp health check failed after $HealthCheckRetries attempts"
                    return $false
                }
                Start-Sleep -Seconds $HealthCheckInterval
            }
        }
        
        if (-not $healthPassed) {
            return $false
        }
    }
    
    Write-SuccessLog "All health checks passed for $TargetEnv environment"
    return $true
}

# Function to switch traffic
function Switch-Traffic {
    param([string]$TargetEnv)
    
    Write-InfoLog "Switching traffic to $TargetEnv environment..."
    
    # Update service selectors
    kubectl patch service "$AppName-frontend-service" -n $Namespace -p "{`"spec`":{`"selector`":{`"version`":`"$TargetEnv`"}}}"
    kubectl patch service "$AppName-backend-service" -n $Namespace -p "{`"spec`":{`"selector`":{`"version`":`"$TargetEnv`"}}}"
    kubectl patch service "$AppName-service" -n $Namespace -p "{`"spec`":{`"selector`":{`"version`":`"$TargetEnv`"}}}"
    
    Write-SuccessLog "Traffic switched to $TargetEnv environment"
}

# Function to verify traffic switch
function Test-TrafficSwitch {
    param([string]$TargetEnv)
    
    Write-InfoLog "Verifying traffic switch to $TargetEnv environment..."
    
    # Get ingress URL
    try {
        $ingressUrl = kubectl get ingress "$AppName-ingress" -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    }
    catch {
        $ingressUrl = ""
    }
    
    $portForwardPid = $null
    if ([string]::IsNullOrEmpty($ingressUrl)) {
        Write-WarningLog "Could not get ingress URL, using port-forward for verification"
        $portForwardJob = Start-Job -ScriptBlock {
            kubectl port-forward service/$using:AppName-service 8080:80 -n $using:Namespace
        }
        Start-Sleep -Seconds 5
        $ingressUrl = "localhost:8080"
        $portForwardPid = $portForwardJob.Id
    }
    
    # Verify backend health through ingress
    $retries = 0
    $verificationPassed = $false
    
    while ($retries -lt $HealthCheckRetries) {
        try {
            $response = Invoke-WebRequest -Uri "http://$ingressUrl/api/health" -TimeoutSec 10 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-SuccessLog "Traffic verification successful - backend responding through ingress"
                $verificationPassed = $true
                break
            }
        }
        catch {
            $retries++
            Write-WarningLog "Traffic verification failed (attempt $retries/$HealthCheckRetries)"
            if ($retries -eq $HealthCheckRetries) {
                Write-ErrorLog "Traffic verification failed after $HealthCheckRetries attempts"
                break
            }
            Start-Sleep -Seconds $HealthCheckInterval
        }
    }
    
    # Cleanup port-forward if used
    if ($portForwardPid) {
        Stop-Job -Id $portForwardPid -ErrorAction SilentlyContinue
        Remove-Job -Id $portForwardPid -ErrorAction SilentlyContinue
    }
    
    if ($verificationPassed) {
        Write-SuccessLog "Traffic switch verification completed"
        return $true
    }
    else {
        return $false
    }
}

# Function to cleanup old environment
function Remove-OldEnvironment {
    param([string]$OldEnv)
    
    Write-InfoLog "Cleaning up $OldEnv environment..."
    
    kubectl delete deployment "$AppName-frontend-$OldEnv" -n $Namespace --ignore-not-found=true
    kubectl delete deployment "$AppName-backend-$OldEnv" -n $Namespace --ignore-not-found=true
    
    Write-SuccessLog "Cleanup of $OldEnv environment completed"
}

# Function to rollback
function Invoke-Rollback {
    param(
        [string]$CurrentEnv,
        [string]$PreviousEnv
    )
    
    Write-WarningLog "Initiating rollback from $CurrentEnv to $PreviousEnv..."
    
    # Check if previous environment deployments exist
    try {
        kubectl get deployment "$AppName-frontend-$PreviousEnv" -n $Namespace 2>$null
        kubectl get deployment "$AppName-backend-$PreviousEnv" -n $Namespace 2>$null
        
        Write-InfoLog "Previous environment deployments found, switching traffic back..."
        Switch-Traffic -TargetEnv $PreviousEnv
        
        if (Test-TrafficSwitch -TargetEnv $PreviousEnv) {
            Write-SuccessLog "Rollback completed successfully"
            Remove-OldEnvironment -OldEnv $CurrentEnv
            return $true
        }
        else {
            Write-ErrorLog "Rollback verification failed"
            return $false
        }
    }
    catch {
        Write-ErrorLog "Previous environment deployments not found, cannot rollback"
        return $false
    }
}

# Main function
function Start-BlueGreenDeployment {
    Write-InfoLog "Starting blue-green deployment for DhakaCart..."
    
    # Check prerequisites
    Test-Prerequisites
    
    # Create temporary directory
    $tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
    
    try {
        # Determine environments
        $currentEnv = Get-CurrentEnvironment
        $targetEnv = Get-TargetEnvironment -CurrentEnv $currentEnv
        
        Write-InfoLog "Current environment: $currentEnv"
        Write-InfoLog "Target environment: $targetEnv"
        Write-InfoLog "Frontend image: $FrontendImage"
        Write-InfoLog "Backend image: $BackendImage"
        
        # Create and deploy to target environment
        New-DeploymentManifests -TargetEnv $targetEnv -TempDir $tempDir.FullName
        Deploy-ToTarget -TargetEnv $targetEnv -TempDir $tempDir.FullName
        
        # Perform health checks
        if (-not (Test-TargetHealth -TargetEnv $targetEnv)) {
            Write-ErrorLog "Health checks failed for $targetEnv environment"
            Write-InfoLog "Cleaning up failed deployment..."
            Remove-OldEnvironment -OldEnv $targetEnv
            exit 1
        }
        
        # Switch traffic
        Switch-Traffic -TargetEnv $targetEnv
        
        # Verify traffic switch
        if (-not (Test-TrafficSwitch -TargetEnv $targetEnv)) {
            Write-ErrorLog "Traffic switch verification failed"
            Write-InfoLog "Attempting rollback..."
            if (Invoke-Rollback -CurrentEnv $targetEnv -PreviousEnv $currentEnv) {
                Write-SuccessLog "Rollback completed"
            }
            else {
                Write-ErrorLog "Rollback failed - manual intervention required"
            }
            exit 1
        }
        
        # Wait for stabilization
        Write-InfoLog "Waiting for deployment to stabilize..."
        Start-Sleep -Seconds 30
        
        # Final verification
        if (Test-TrafficSwitch -TargetEnv $targetEnv) {
            Write-SuccessLog "Deployment stabilized successfully"
            Remove-OldEnvironment -OldEnv $currentEnv
            Write-SuccessLog "Blue-green deployment completed successfully!"
            Write-InfoLog "Active environment: $targetEnv"
        }
        else {
            Write-ErrorLog "Final verification failed"
            Write-InfoLog "Attempting rollback..."
            if (Invoke-Rollback -CurrentEnv $targetEnv -PreviousEnv $currentEnv) {
                Write-SuccessLog "Rollback completed"
            }
            else {
                Write-ErrorLog "Rollback failed - manual intervention required"
            }
            exit 1
        }
    }
    finally {
        # Cleanup temporary directory
        Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Run the deployment
Start-BlueGreenDeployment