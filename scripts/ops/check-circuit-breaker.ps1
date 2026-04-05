# Check circuit breaker status and LULD bands for all symbols
$backendUrl = "http://localhost:8090"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Circuit Breaker & LULD Analysis"
Write-Host "============================================================`n" -ForegroundColor Cyan

# Check circuit breaker status
Write-Host "Fetching circuit breaker status..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$backendUrl/api/system/circuit-breakers" `
        -Method GET `
        -UseBasicParsing `
        -ErrorAction SilentlyContinue
    
    if ($response) {
        $status = $response.Content | ConvertFrom-Json
        Write-Host "Circuit Breaker Status:" -ForegroundColor Green
        
        if ($status.symbolHalts) {
            Write-Host "  Halted Symbols:" -ForegroundColor Yellow
            foreach ($symbol in $status.symbolHalts.PSObject.Properties.Name) {
                $halt = $status.symbolHalts.$symbol
                Write-Host "    ❌ $symbol - Halted: Reason=$($halt.reason)" -ForegroundColor Red
            }
        } else {
            Write-Host "  No symbols currently halted" -ForegroundColor Green
        }
        
        if ($status.luldBands) {
            Write-Host "`n  LULD Bands:" -ForegroundColor Green
            foreach ($symbol in $status.luldBands.PSObject.Properties.Name) {
                $band = $status.luldBands.$symbol
                Write-Host "    $($symbol):" -ForegroundColor Cyan
                Write-Host "      Reference: $($band.referencePrice)" -ForegroundColor Gray
                Write-Host "      Valid Range: $($band.lowerLimit) - $($band.upperLimit)" -ForegroundColor Gray
            }
        }
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Try to resume all symbols
Write-Host "`n`nAttempting to resume trading for all symbols..." -ForegroundColor Cyan

$symbols = @("AAPL", "MSFT", "GOOGL", "AMZN")
foreach ($symbol in $symbols) {
    try {
        $response = Invoke-WebRequest -Uri "$backendUrl/api/system/circuit-breakers/$symbol/resume" `
            -Method POST `
            -UseBasicParsing `
            -ErrorAction SilentlyContinue
        
        if ($response.StatusCode -eq 200) {
            Write-Host "  ✓ $symbol - Trading resumed" -ForegroundColor Green
        }
    } catch {
        Write-Host "  - $symbol - No action needed (likely already trading)" -ForegroundColor Gray
    }
}

# Get updated LULD bands
Write-Host "`n`nUpdated LULD Bands for Testing:" -ForegroundColor Cyan
foreach ($symbol in $symbols) {
    try {
        $response = Invoke-WebRequest -Uri "$backendUrl/api/system/circuit-breakers/$symbol/luld" `
            -Method GET `
            -UseBasicParsing `
            -ErrorAction SilentlyContinue
        
        if ($response) {
            $band = $response.Content | ConvertFrom-Json
            Write-Host "  $($symbol):" -ForegroundColor Green
            Write-Host "    Reference Price: $($band.referencePrice)" -ForegroundColor Gray
            Write-Host "    Lower Limit: $($band.lowerLimit)" -ForegroundColor Gray
            Write-Host "    Upper Limit: $($band.upperLimit)" -ForegroundColor Gray
            Write-Host "    Band %: $($band.bandPercent * 100)%" -ForegroundColor Gray
            Write-Host "    ✓ Use prices between $($band.lowerLimit) and $($band.upperLimit)" -ForegroundColor Yellow
        }
    } catch {
        # Silently skip if endpoint not available
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Recommendation: Use reference price +/- 2% as test prices" -ForegroundColor Yellow
Write-Host "Example: If AAPL ref is 100, use prices like 101, 102, 99, 98" -ForegroundColor Yellow
Write-Host "============================================================`n" -ForegroundColor Cyan
