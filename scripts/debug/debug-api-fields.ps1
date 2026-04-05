# Detailed API debugging - test each field combination
$BaseUrl = "http://localhost:8090/api"

Write-Host "Testing minimal request with FIX format..." -ForegroundColor Cyan

# Test 1: Absolutely minimal request
Write-Host "`n1. Test minimal request:" -ForegroundColor Yellow
$minimal = @{
    symbol = "TEST"
    side = "1"
    quantity = 1
    price = 100
    orderType = "2"
} | ConvertTo-Json

Write-Host "Request: $minimal"
try {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" -Method POST -Body $minimal -ContentType "application/json" -TimeoutSec 5
    Write-Host "SUCCESS: $($resp |ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

# Test 2: With timeInForce
Write-Host "`n2. Test with timeInForce:" -ForegroundColor Yellow
$withTIF = @{
    symbol = "TEST"
    side = "1"
    quantity = 1
    price = 100.0
    orderType = "2"
    timeInForce = "0"
} | ConvertTo-Json

Write-Host "Request: $withTIF"
try {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" -Method POST -Body $withTIF -ContentType "application/json" -TimeoutSec 5
    Write-Host "SUCCESS: $($resp | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

# Test 3: With clientId only
Write-Host "`n3. Test with clientId:" -ForegroundColor Yellow
$withClient = @{
    symbol = "TEST"
    side = "1"
    quantity = 1
    price = 100.0
    orderType = "2"
    clientId = "CLIENT1"
} | ConvertTo-Json

Write-Host "Request: $withClient"
try {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" -Method POST -Body $withClient -ContentType "application/json" -TimeoutSec 5
    Write-Host "SUCCESS: $($resp | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

# Test 4: Full request like the test
Write-Host "`n4. Test full request (like OrderManagementEndToEndTest):" -ForegroundColor Yellow
$full = @{
    symbol = "TEST"
    side = "1"
    quantity = [int]25
    price = [double]100.0
    orderType = "2"
    timeInForce = "0"
    clientId = "CLIENT1"
    clOrdId = "ORD-$(New-Guid)"
} | ConvertTo-Json

Write-Host "Request: $full"
try {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" -Method POST -Body $full -ContentType "application/json" -TimeoutSec 5
    Write-Host "SUCCESS: $($resp | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

Write-Host "`nDebug complete." -ForegroundColor Cyan
