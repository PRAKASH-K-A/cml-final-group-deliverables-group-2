# Simple diagnostic test
$BaseUrl = "http://localhost:8090/api"

Write-Host "Testing direct API connectivity..." -ForegroundColor Cyan

# Test 1: Health check
try {
    Write-Host "1. Testing health endpoint..."
    $health = Invoke-RestMethod -Uri "$BaseUrl/system/health" -TimeoutSec 5
    Write-Host "   SUCCESS: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Submit single order
try {
    Write-Host "2. Testing order submission..."
    $body = @{
        symbol = "DIAG"
        side = "BUY"
        orderType = "LIMIT"
        limitPrice = 100.0
        quantity = 10
    } | ConvertTo-Json
    
    Write-Host "   Request body: $body"
    
    $response = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" `
        -Method POST `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 5
    
    Write-Host "   SUCCESS: Order ref = $($response.orderRefNumber)" -ForegroundColor Green
    Write-Host "   Full response: $($response | ConvertTo-Json)" -ForegroundColor Cyan
    
} catch {
    Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Details: $($_.Exception | ConvertTo-Json)" -ForegroundColor Yellow
}

# Test 3: Check if orders are being persisted
try {
    Write-Host "3. Checking order audit..."
    $audit = Invoke-RestMethod -Uri "$BaseUrl/orders/audit" -TimeoutSec 5
    Write-Host "   Audit endpoint accessible" -ForegroundColor Green
    Write-Host "   Response type: $($audit.GetType())" -ForegroundColor Cyan
} catch {
    Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nDiagnostics complete." -ForegroundColor Cyan
