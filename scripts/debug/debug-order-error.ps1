# Debug order submission error
$BaseUrl = "http://localhost:8090/api"

Write-Host "Debugging order submission error..." -ForegroundColor Cyan

try {
    $body = @{
        symbol = "GOOG"
        side = "BUY"
        orderType = "LIMIT"
        limitPrice = 300.0
        quantity = 100
    } | ConvertTo-Json
    
    Write-Host "Request body:"
    Write-Host $body
    Write-Host ""
    
    $response = Invoke-RestMethod -Uri "$BaseUrl/orders/orchestrated" `
        -Method POST `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 5
    
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
    
} catch {
    # Extract the actual error message from the response
    Write-Host "HTTP Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    
    # Try to read response stream
    try {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errorBody = $reader.ReadToEnd()
        $reader.Close()
        Write-Host "Server response:" -ForegroundColor Yellow
        Write-Host $errorBody -ForegroundColor Yellow
    } catch {
        Write-Host "Could not read error body: $($_.Exception.Message)"
    }
}
