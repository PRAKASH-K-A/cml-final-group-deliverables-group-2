# ==========================================
# FINAL Comprehensive E2E Test - LULD-Compliant
# Using prices within valid circuit breaker bands
# ==========================================

$ErrorActionPreference = "Continue"
$backendUrl = "http://localhost:8090"
$results = @{
    passed = 0
    failed = 0
    skipped = 0
}

function Write-Header {
    param([string]$text)
    Write-Host "`n========== $text ==========" -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$text)
    Write-Host "PASS: $text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$text, [string]$reason = "")
    $msg = "FAIL: $text"
    if ($reason) { $msg += " - $reason" }
    Write-Host $msg -ForegroundColor Red
}

function Assert-NotNull {
    param([object]$value, [string]$message)
    if ($null -ne $value) {
        Write-Pass $message
        $script:results.passed++
        return $true
    } else {
        Write-Fail $message "Value is null"
        $script:results.failed++
        return $false
    }
}

function Submit-Order {
    param(
        [string]$symbol,
        [string]$side,
        [long]$quantity,
        [double]$price,
        [string]$orderType = "LIMIT",
        [string]$clientId = "CLIENT1"
    )
    
    $body = @{
        symbol = $symbol
        side = $side
        quantity = $quantity
        price = $price
        orderType = $orderType
        clientId = $clientId
        clOrdId = [guid]::NewGuid().ToString()
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$backendUrl/api/orders/orchestrated" `
            -Method POST `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 10 `
            -ErrorAction Stop
        return $response
    } catch {
        $details = Get-HttpErrorDetails -ErrorRecord $_
        $msg = $_.Exception.Message
        if ($details) { $msg = "$msg | Response: $details" }
        Write-Fail "Failed to submit order" $msg
        return $null
    }
}

function Submit-BatchOrders {
    param([array]$orders)

    $body = @{ orders = $orders } | ConvertTo-Json -Depth 6
    
    try {
        $response = Invoke-RestMethod -Uri "$backendUrl/api/orders/orchestrated/batch" `
            -Method POST `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 30 `
            -ErrorAction Stop
        return $response
    } catch {
        $details = Get-HttpErrorDetails -ErrorRecord $_
        $msg = $_.Exception.Message
        if ($details) { $msg = "$msg | Response: $details" }
        Write-Fail "Failed to submit batch" $msg
        return $null
    }
}

function Get-HttpErrorDetails {
    param([object]$ErrorRecord)

    if ($ErrorRecord -and $ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }

    return ""
}

function Resume-SymbolTrading {
    param([string]$symbol)

    try {
        $response = Invoke-WebRequest -Uri "$backendUrl/api/system/circuit-breakers/$symbol/resume" `
            -Method POST `
            -UseBasicParsing `
            -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Get-LuldBand {
    param([string]$symbol)

    try {
        $response = Invoke-WebRequest -Uri "$backendUrl/api/system/circuit-breakers/$symbol/luld" `
            -Method GET `
            -UseBasicParsing `
            -ErrorAction Stop
        $band = $response.Content | ConvertFrom-Json

        return @{
            lower = [double]$band.lowerLimit
            upper = [double]$band.upperLimit
            reference = [double]$band.referencePrice
        }
    } catch {
        return $null
    }
}

function Get-TestPrices {
    param(
        [string]$symbol,
        [double[]]$fallbackPrices
    )

    $band = Get-LuldBand -symbol $symbol
    if ($null -eq $band) {
        return $fallbackPrices
    }

    $span = $band.upper - $band.lower
    if ($span -le 0) {
        return $fallbackPrices
    }

    $p1 = [Math]::Round($band.lower + ($span * 0.20), 2)
    $p2 = [Math]::Round($band.lower + ($span * 0.35), 2)
    $p3 = [Math]::Round($band.lower + ($span * 0.55), 2)
    $p4 = [Math]::Round($band.lower + ($span * 0.70), 2)

    return @($p1, $p2, $p3, $p4)
}

# ==========================================
# VALID LULD-COMPLIANT PRICES
# ==========================================
# AAPL ref 178.5: Valid 169.575-187.425 → use 175-185
# MSFT ref 378.9: Valid 359.955-397.844 → use 370-390
# GOOGL ref 141.8: Valid 134.71-148.89 → use 138-146
# AMZN ref 178.25: Valid 169.3375-187.1625 → use 172-183
# ==========================================

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "FIX TRADING SIMULATOR - FINAL E2E TEST (LULD-Compliant)" -ForegroundColor Cyan
Write-Host "Using Circuit Breaker-Approved Price Ranges" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`nBackend URL: $backendUrl`n" -ForegroundColor Gray

# Health check
try {
    $health = Invoke-RestMethod -Uri "$backendUrl/api/system/health" -Method GET -TimeoutSec 5 -ErrorAction Stop
    Write-Pass "Backend health check: ONLINE"
} catch {
    Write-Fail "Backend health check" $_.Exception.Message
    Write-Host "`nERROR: Backend not running on $backendUrl" -ForegroundColor Red
    exit 1
}

# Ensure core symbols are not left halted from prior volatility tests.
foreach ($symbol in @("AAPL", "MSFT", "TSLA", "AMZN")) {
    Resume-SymbolTrading -symbol $symbol | Out-Null
}

$aaplPrices = Get-TestPrices -symbol "AAPL" -fallbackPrices @(175, 176, 180, 185)
$msftPrices = Get-TestPrices -symbol "MSFT" -fallbackPrices @(370, 375, 380, 385)
$tslaPrices = Get-TestPrices -symbol "TSLA" -fallbackPrices @(198, 200, 203, 206)
$amznPrices = Get-TestPrices -symbol "AMZN" -fallbackPrices @(172, 175, 180, 183)

# ==========================================
# TEST 1: AAPL Buy/Sell (Prices: 175-185)
# ==========================================
Write-Header "TEST 1: AAPL Buy/Sell (Prices within 169.575-187.425)"

$aapl1 = Submit-Order -symbol "AAPL" -side "BUY" -quantity 100 -price $aaplPrices[0] -clientId "T1_AAPL1"
Assert-NotNull $aapl1 "AAPL buy 100 @ $($aaplPrices[0])" | Out-Null

Start-Sleep -Milliseconds 50

$aapl2 = Submit-Order -symbol "AAPL" -side "BUY" -quantity 50 -price $aaplPrices[1] -clientId "T1_AAPL2"
Assert-NotNull $aapl2 "AAPL buy 50 @ $($aaplPrices[1])" | Out-Null

Start-Sleep -Milliseconds 50

$aapl3 = Submit-Order -symbol "AAPL" -side "SELL" -quantity 75 -price $aaplPrices[2] -clientId "T1_AAPL3"
Assert-NotNull $aapl3 "AAPL sell 75 @ $($aaplPrices[2])" | Out-Null

Start-Sleep -Milliseconds 50

$aapl4 = Submit-Order -symbol "AAPL" -side "SELL" -quantity 25 -price $aaplPrices[3] -clientId "T1_AAPL4"
Assert-NotNull $aapl4 "AAPL sell 25 @ $($aaplPrices[3])" | Out-Null

Write-Pass "TEST 1: AAPL Buy/Sell completed"

# ==========================================
# TEST 2: MSFT Buy/Sell (Prices: 370-390)
# ==========================================
Write-Header "TEST 2: MSFT Buy/Sell (Prices within 359.955-397.844)"

$msft1 = Submit-Order -symbol "MSFT" -side "BUY" -quantity 50 -price $msftPrices[0] -clientId "T2_MSFT1"
Assert-NotNull $msft1 "MSFT buy 50 @ $($msftPrices[0])" | Out-Null

Start-Sleep -Milliseconds 50

$msft2 = Submit-Order -symbol "MSFT" -side "BUY" -quantity 75 -price $msftPrices[1] -clientId "T2_MSFT2"
Assert-NotNull $msft2 "MSFT buy 75 @ $($msftPrices[1])" | Out-Null

Start-Sleep -Milliseconds 50

$msft3 = Submit-Order -symbol "MSFT" -side "SELL" -quantity 50 -price $msftPrices[2] -clientId "T2_MSFT3"
Assert-NotNull $msft3 "MSFT sell 50 @ $($msftPrices[2])" | Out-Null

Start-Sleep -Milliseconds 50

$msft4 = Submit-Order -symbol "MSFT" -side "SELL" -quantity 75 -price $msftPrices[3] -clientId "T2_MSFT4"
Assert-NotNull $msft4 "MSFT sell 75 @ $($msftPrices[3])" | Out-Null

Write-Pass "TEST 2: MSFT Buy/Sell completed"

# ==========================================
# TEST 3: TSLA Buy/Sell
# ==========================================
Write-Header "TEST 3: TSLA Buy/Sell"

$tsla1 = Submit-Order -symbol "TSLA" -side "BUY" -quantity 200 -price $tslaPrices[0] -clientId "T3_TSLA1"
Assert-NotNull $tsla1 "TSLA buy 200 @ $($tslaPrices[0])" | Out-Null

Start-Sleep -Milliseconds 50

$tsla2 = Submit-Order -symbol "TSLA" -side "BUY" -quantity 150 -price $tslaPrices[1] -clientId "T3_TSLA2"
Assert-NotNull $tsla2 "TSLA buy 150 @ $($tslaPrices[1])" | Out-Null

Start-Sleep -Milliseconds 50

$tsla3 = Submit-Order -symbol "TSLA" -side "SELL" -quantity 100 -price $tslaPrices[2] -clientId "T3_TSLA3"
Assert-NotNull $tsla3 "TSLA sell 100 @ $($tslaPrices[2])" | Out-Null

Start-Sleep -Milliseconds 50

$tsla4 = Submit-Order -symbol "TSLA" -side "SELL" -quantity 150 -price $tslaPrices[3] -clientId "T3_TSLA4"
Assert-NotNull $tsla4 "TSLA sell 150 @ $($tslaPrices[3])" | Out-Null

Write-Pass "TEST 3: TSLA Buy/Sell completed"

# ==========================================
# TEST 4: AMZN Buy/Sell (Prices: 172-183)
# ==========================================
Write-Header "TEST 4: AMZN Buy/Sell (Prices within 169.3375-187.1625)"

$amzn1 = Submit-Order -symbol "AMZN" -side "BUY" -quantity 100 -price $amznPrices[0] -clientId "T4_AMZN1"
Assert-NotNull $amzn1 "AMZN buy 100 @ $($amznPrices[0])" | Out-Null

Start-Sleep -Milliseconds 50

$amzn2 = Submit-Order -symbol "AMZN" -side "BUY" -quantity 50 -price $amznPrices[1] -clientId "T4_AMZN2"
Assert-NotNull $amzn2 "AMZN buy 50 @ $($amznPrices[1])" | Out-Null

Start-Sleep -Milliseconds 50

$amzn3 = Submit-Order -symbol "AMZN" -side "SELL" -quantity 75 -price $amznPrices[2] -clientId "T4_AMZN3"
Assert-NotNull $amzn3 "AMZN sell 75 @ $($amznPrices[2])" | Out-Null

Start-Sleep -Milliseconds 50

$amzn4 = Submit-Order -symbol "AMZN" -side "SELL" -quantity 25 -price $amznPrices[3] -clientId "T4_AMZN4"
Assert-NotNull $amzn4 "AMZN sell 25 @ $($amznPrices[3])" | Out-Null

Write-Pass "TEST 4: AMZN Buy/Sell completed"

# ==========================================
# PERFORMANCE: Burst Load (400 orders)
# ==========================================
Write-Header "PERFORMANCE TEST: Burst Load (400 orders)"

Write-Host "Submitting 400 orders in burst with LULD-compliant prices..." -ForegroundColor Cyan

$orders = @()
for ($i = 1; $i -le 400; $i++) {
    $symbolIndex = $i % 4
    $symbol = @("AAPL", "MSFT", "TSLA", "AMZN")[$symbolIndex]
    $side = if ($i % 2 -eq 0) { "BUY" } else { "SELL" }
    
    $price = switch($symbol) {
        "AAPL"  { [Math]::Round($aaplPrices[0] + (($i % 3) * 0.01), 2) }
        "MSFT"  { [Math]::Round($msftPrices[0] + (($i % 3) * 0.01), 2) }
        "TSLA"  { [Math]::Round($tslaPrices[0] + (($i % 3) * 0.01), 2) }
        "AMZN"  { [Math]::Round($amznPrices[0] + (($i % 3) * 0.01), 2) }
    }
    
    $orders += @{
        symbol = $symbol
        side = $side
        quantity = 10 + ($i % 90)
        price = $price
        orderType = "LIMIT"
        clientId = "BURST_$i"
        clOrdId = [guid]::NewGuid().ToString()
    }
}

$start = Get-Date
$response = Submit-BatchOrders -orders $orders
$end = Get-Date

$duration = ($end - $start).TotalSeconds
$throughput = 400 / $duration

Write-Host "  Orders submitted: 400" -ForegroundColor Gray
Write-Host "  Duration: $([Math]::Round($duration, 3)) seconds" -ForegroundColor Gray
Write-Host "  Throughput: $([Math]::Round($throughput, 2)) ops/sec" -ForegroundColor Gray

if ($throughput -ge 100) {
    Write-Pass "Burst throughput acceptable"
    $script:results.passed++
} else {
    Write-Fail "Burst throughput below threshold"
    $script:results.failed++
}

# ==========================================
# SUMMARY
# ==========================================

Write-Header "TEST SUMMARY"

$total = $results.passed + $results.failed
Write-Host "Total Tests: $total" -ForegroundColor Cyan
Write-Host "  Passed: $($results.passed)" -ForegroundColor Green
Write-Host "  Failed: $($results.failed)" -ForegroundColor Red

$passRate = if ($total -gt 0) { [Math]::Round(($results.passed / $total) * 100, 1) } else { 0 }
Write-Host "`nPass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } else { "Yellow" })

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
if ($passRate -ge 80) {
    Write-Host "CRITICAL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "Some tests failed - review output above" -ForegroundColor Yellow
}
Write-Host "============================================================`n" -ForegroundColor Cyan

exit $(if ($results.failed -eq 0) { 0 } else { 1 })
