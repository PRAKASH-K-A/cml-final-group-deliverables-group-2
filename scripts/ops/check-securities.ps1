# Check available symbols in the system
$backendUrl = "http://localhost:8090"

Write-Host "Fetching available securities..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "$backendUrl/api/system/securities" `
        -Method GET `
        -ContentType "application/json" `
        -TimeoutSec 10 `
        -UseBasicParsing `
        -ErrorAction SilentlyContinue
    
    if ($response) {
        $securities = $response.Content | ConvertFrom-Json
        Write-Host "Securities Response:" -ForegroundColor Cyan
        Write-Host $($securities | ConvertTo-Json -Depth 3) -ForegroundColor Gray
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
