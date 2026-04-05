# Open the market to enable trading
$backendUrl = "http://localhost:8090"

Write-Host "Opening market..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "$backendUrl/api/system/market/open?reason=e2e-test" `
        -Method POST `
        -ContentType "application/json" `
        -TimeoutSec 10 `
        -UseBasicParsing `
        -ErrorAction SilentlyContinue
    
    if ($response) {
        Write-Host "Response Status: $($response.StatusCode)" -ForegroundColor Gray
        Write-Host "Response Content: $($response.Content)" -ForegroundColor Gray
        
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 204) {
            Write-Host "Market opened successfully!" -ForegroundColor Green
        } else {
            Write-Host "Market open returned status: $($response.StatusCode)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No response received" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Verify system health
Write-Host "`nVerifying system health..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$backendUrl/api/system/health" `
        -Method GET `
        -ContentType "application/json" `
        -TimeoutSec 10 `
        -UseBasicParsing `
        -ErrorAction SilentlyContinue
    
    if ($response) {
        $health = $response.Content | ConvertFrom-Json
        Write-Host "System Health Response:" -ForegroundColor Gray
        $health | ConvertTo-Json | Write-Host -ForegroundColor Gray
    }
} catch {
    Write-Host "Error checking health: $($_.Exception.Message)" -ForegroundColor Red
}
