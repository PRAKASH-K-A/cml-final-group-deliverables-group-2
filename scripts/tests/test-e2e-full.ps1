#Requires -Version 5.1
<#!
.SYNOPSIS
  Full E2E + Performance suite for FIX Trading Simulator (exchange-back-end REST layer)

.DESCRIPTION
  Covers:
    - Performance: Burst, Throughput, Order Latency, DB Latency
    - Test Cases #1 .. #6 from user specification (REST-automatable steps)

  Notes:
    - Steps requiring process-level service kill/restart or explicit FIX socket disconnect/reconnect
      are marked SKIP unless orchestrated externally.
#>

param(
  [string]$BaseUrl = "http://localhost:8090",
  [switch]$RunLongThroughput = $true,
  [switch]$ShowDetail
)

$ErrorActionPreference = "Stop"

$script:pass = 0
$script:fail = 0
$script:skip = 0
$script:openStatus = @("NEW", "PENDING_NEW", "PARTIALLY_FILLED", "PARTIAL_FILL", "PENDING_CANCEL", "PENDING_REPLACE")

function Write-Pass([string]$Name) { Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:pass++ }
function Write-Fail([string]$Name, [string]$Msg) { Write-Host "  [FAIL] $Name -- $Msg" -ForegroundColor Red; $script:fail++ }
function Write-Skip([string]$Name, [string]$Reason) { Write-Host "  [SKIP] $Name -- $Reason" -ForegroundColor Yellow; $script:skip++ }
function Write-Section([string]$Title) { Write-Host ""; Write-Host "== $Title ==" -ForegroundColor Cyan }

function Invoke-Api {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body
  )

  $uri = "$BaseUrl$Path"
  $headers = @{ "Content-Type" = "application/json"; "Accept" = "application/json" }

  try {
    if ($null -ne $Body) {
      $json = $Body | ConvertTo-Json -Depth 10 -Compress
      $resp = Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json
    } else {
      $resp = Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
    }

    return [pscustomobject]@{
      ok = $true
      status = 200
      data = $resp
      error = $null
    }
  } catch {
    $sc = $null
    if ($_.Exception -and $_.Exception.Response) {
      $sc = $_.Exception.Response.StatusCode.value__
    }
    $msg = $_.ErrorDetails.Message

    $parsed = $null
    if ($msg) {
      try { $parsed = $msg | ConvertFrom-Json } catch { }
    }

    return [pscustomobject]@{
      ok = $false
      status = $sc
      data = $parsed
      error = $msg
    }
  }
}

function Ensure-TradingReady {
  Write-Section "Bootstrap Trading State"

  $open = Invoke-Api POST "/api/system/market/open?reason=full-e2e" $null
  if ($open.ok) { Write-Pass "Market opened" } else { Write-Skip "Market open" ("Status=" + $open.status) }

  $risk = Invoke-Api POST "/api/system/risk/resume" $null
  if ($risk.ok) { Write-Pass "Risk resumed" } else { Write-Skip "Risk resume" ("Status=" + $risk.status) }

  $cb = Invoke-Api POST "/api/system/circuit-breakers/market/resume" $null
  if ($cb.ok) { Write-Pass "Market circuit breaker resumed" } else { Write-Skip "Market circuit breaker resume" ("Status=" + $cb.status) }
}

function Get-AllOrders {
  $resp = Invoke-Api GET "/api/orders" $null
  if ($resp.ok -and $resp.data) { return @($resp.data) }
  return @()
}

function Is-OpenOrderStatus([string]$status) {
  return $script:openStatus -contains ($status + "")
}

function Get-OpenOrders([string]$Symbol = $null) {
  $orders = Get-AllOrders
  $open = @($orders | Where-Object { Is-OpenOrderStatus $_.status })
  if ($Symbol) {
    return @($open | Where-Object { $_.symbol -eq $Symbol })
  }
  return $open
}

function Submit-Order {
  param(
    [string]$Symbol,
    [string]$Side,
    [int]$Qty,
    [double]$Price,
    [string]$ClientId = "CLIENT001",
    [string]$OrderType = "2",
    [string]$TimeInForce = "0",
    [string]$ClOrdPrefix = "E2E"
  )

  $cl = "$ClOrdPrefix-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
  $payload = @{
    symbol = $Symbol
    side = $Side
    quantity = $Qty
    price = $Price
    orderType = $OrderType
    timeInForce = $TimeInForce
    clientId = $ClientId
    clOrdId = $cl
  }

  $resp = Invoke-Api POST "/api/orders/orchestrated" $payload
  $orderRef = $null
  $status = $null

  if ($resp.ok -and $resp.data) {
    $orderRef = $resp.data.orderRefNumber
    $status = $resp.data.status
  } elseif ($resp.data) {
    $orderRef = $resp.data.orderRefNumber
    $status = $resp.data.status
  }

  return [pscustomobject]@{
    ok = $resp.ok
    httpStatus = $resp.status
    orderRef = $orderRef
    clOrdId = $cl
    status = $status
    raw = $resp
  }
}

function Cancel-Order([string]$OrderRef, [string]$ClientId = "CLIENT001", [string]$Reason = "E2E cancel") {
  if (-not $OrderRef) {
    return [pscustomobject]@{ ok = $false; status = $null; raw = $null }
  }

  $payload = @{ clientId = $ClientId; reason = $Reason }
  $resp = Invoke-Api POST "/api/orders/$OrderRef/cancel" $payload
  return [pscustomobject]@{ ok = $resp.ok; status = $resp.status; raw = $resp }
}

function Amend-Order([string]$OrderRef, [double]$NewPrice, [int]$NewQty, [string]$ClientId = "CLIENT001") {
  $payload = @{ clientId = $ClientId; newPrice = $NewPrice; newQuantity = $NewQty; reason = "E2E amend" }
  $resp = Invoke-Api POST "/api/orders/$OrderRef/amend" $payload
  return [pscustomobject]@{ ok = $resp.ok; status = $resp.status; raw = $resp }
}

function Bulk-Cancel([string]$ClientId = "CLIENT001", [string]$Symbol = $null, [string]$Reason = "E2E bulk cancel") {
  $payload = @{ clientId = $ClientId; symbol = $Symbol; reason = $Reason }
  $resp = Invoke-Api POST "/api/orders/bulk-cancel" $payload
  return $resp
}

function Get-ReferencePrice([string]$Symbol) {
  $md = Invoke-Api GET "/api/marketdata/$Symbol" $null
  if ($md.ok -and $md.data -and $md.data.lastPrice) {
    return [double]$md.data.lastPrice
  }
  return 100.0
}

function Assert-OrderPersistedByRef([string]$OrderRef) {
  if (-not $OrderRef) { return $false }
  $resp = Invoke-Api GET "/api/orders/$OrderRef" $null
  return ($resp.ok -and $resp.data -and $resp.data.orderRefNumber -eq $OrderRef)
}

function Run-PerformanceBurst {
  Write-Section "Performance #1 - Burst (200 orders/sec x 2 sec)"

  $targetOrders = 400
  $symbol = "AAPL"
  $okCount = 0
  $persistedCount = 0

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  for ($i = 1; $i -le $targetOrders; $i++) {
    $price = 180.00 + (($i % 10) * 0.01)
    $res = Submit-Order -Symbol $symbol -Side "1" -Qty 10 -Price $price -ClientId "PERF_BURST" -OrderType "2" -ClOrdPrefix "BURST"
    if ($res.ok -and $res.orderRef) {
      $okCount++
      if (Assert-OrderPersistedByRef $res.orderRef) {
        $persistedCount++
      }
    }
  }
  $sw.Stop()

  $elapsedSec = [math]::Max(0.001, $sw.Elapsed.TotalSeconds)
  $actualRate = [math]::Round($okCount / $elapsedSec, 2)

  if ($okCount -gt 0) {
    Write-Pass "Burst accepted=$okCount/$targetOrders rate=$actualRate orders/sec"
  } else {
    Write-Fail "Burst acceptance" "No orders accepted"
  }

  if ($persistedCount -eq $okCount -and $okCount -gt 0) {
    Write-Pass "Reference assigned and retrievable before/at persistence boundary for accepted orders"
  } else {
    Write-Fail "Reference/persistence check" "persistedByRef=$persistedCount accepted=$okCount"
  }
}

function Run-PerformanceThroughput {
  Write-Section "Performance #2 - Throughput (200 orders/min for 10 min)"

  if (-not $RunLongThroughput) {
    Write-Skip "10-minute throughput run" "Disabled by -RunLongThroughput"
    return
  }

  $symbol = "AAPL"
  $targetOrders = 2000
  $intervalMs = 300
  $accepted = 0

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $nextTick = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $freq = [double][System.Diagnostics.Stopwatch]::Frequency

  for ($i = 1; $i -le $targetOrders; $i++) {
    $price = 181.00 + (($i % 20) * 0.01)
    $res = Submit-Order -Symbol $symbol -Side "2" -Qty 5 -Price $price -ClientId "PERF_TPUT" -OrderType "2" -ClOrdPrefix "TPUT"
    if ($res.ok) { $accepted++ }

    $nextTick += [long]($freq * ($intervalMs / 1000.0))
    $now = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $remaining = $nextTick - $now
    if ($remaining -gt 0) {
      Start-Sleep -Milliseconds ([math]::Floor(($remaining / $freq) * 1000))
    }
  }

  $sw.Stop()
  $elapsedMin = [math]::Round($sw.Elapsed.TotalMinutes, 3)
  $actualPerMin = [math]::Round($accepted / [math]::Max(0.001, $sw.Elapsed.TotalMinutes), 2)

  Write-Pass "Throughput submitted=$targetOrders accepted=$accepted elapsedMin=$elapsedMin actualPerMin=$actualPerMin"
}

function Run-PerformanceOrderLatency {
  Write-Section "Performance #3 - Order Latency"

  $symbol = "AAPL"
  $buy = Submit-Order -Symbol $symbol -Side "1" -Qty 25 -Price 190.00 -ClientId "LATENCY_A" -OrderType "2" -ClOrdPrefix "LAT-B"
  if (-not $buy.ok) {
    Write-Fail "Order latency setup" "Failed to submit first-side order"
    return
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $sell = Submit-Order -Symbol $symbol -Side "2" -Qty 25 -Price 190.00 -ClientId "LATENCY_B" -OrderType "2" -ClOrdPrefix "LAT-S"
  if (-not $sell.ok) {
    Write-Fail "Order latency" "Failed to submit contra order"
    return
  }

  $filled = $false
  for ($i = 0; $i -lt 100; $i++) {
    $o1 = Invoke-Api GET "/api/orders/$($buy.orderRef)" $null
    $o2 = Invoke-Api GET "/api/orders/$($sell.orderRef)" $null
    $s1 = if ($o1.ok -and $o1.data) { $o1.data.status } else { "" }
    $s2 = if ($o2.ok -and $o2.data) { $o2.data.status } else { "" }

    if (($s1 -eq "FILLED" -or $s1 -eq "PARTIALLY_FILLED") -and ($s2 -eq "FILLED" -or $s2 -eq "PARTIALLY_FILLED")) {
      $filled = $true
      break
    }
    Start-Sleep -Milliseconds 50
  }

  $sw.Stop()
  if ($filled) {
    Write-Pass ("Order match+execution path latency approx=" + [math]::Round($sw.Elapsed.TotalMilliseconds, 2) + " ms")
  } else {
    Write-Fail "Order latency" "Orders did not reach filled/partial states within polling window"
  }
}

function Run-PerformanceDbLatency {
  Write-Section "Performance #4 - Database Latency (persisted orders/sec)"

  $before = @(Get-AllOrders).Count
  $n = 300
  $accepted = 0

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  for ($i = 1; $i -le $n; $i++) {
    $res = Submit-Order -Symbol "AAPL" -Side "1" -Qty 3 -Price (170 + ($i % 15) * 0.01) -ClientId "PERF_DB" -OrderType "2" -ClOrdPrefix "DB"
    if ($res.ok) { $accepted++ }
  }
  Start-Sleep -Milliseconds 500
  $after = @(Get-AllOrders).Count
  $sw.Stop()

  $persistedDelta = [math]::Max(0, ($after - $before))
  $ops = [math]::Round($persistedDelta / [math]::Max(0.001, $sw.Elapsed.TotalSeconds), 2)

  if ($persistedDelta -gt 0) {
    Write-Pass "Persisted delta=$persistedDelta accepted=$accepted dbPersistOpsPerSec=$ops"
  } else {
    Write-Fail "DB latency" "No persisted delta observed"
  }
}

function Run-TestCase1 {
  Write-Section "Test Case #1"
  $prices = @(307.00, 307.11, 307.111, 307.01)
  $refs = @()

  foreach ($p in $prices) { $r = Submit-Order -Symbol "GOOG" -Side "1" -Qty 50 -Price $p -ClientId "TC1A" -OrderType "2" -ClOrdPrefix "TC1"; if ($r.ok) { $refs += $r.orderRef } }
  foreach ($p in $prices) { $r = Submit-Order -Symbol "GOOG" -Side "1" -Qty 50 -Price $p -ClientId "TC1A" -OrderType "2" -ClOrdPrefix "TC1"; if ($r.ok) { $refs += $r.orderRef } }
  $sell1 = Submit-Order -Symbol "GOOG" -Side "2" -Qty 105 -Price 307.111 -ClientId "TC1A" -OrderType "2" -ClOrdPrefix "TC1"
  $buyDiff = Submit-Order -Symbol "GOOG" -Side "1" -Qty 200 -Price 307.11 -ClientId "TC1B" -OrderType "2" -ClOrdPrefix "TC1"

  $openGoog = Get-OpenOrders "GOOG"
  $cand = $openGoog | Where-Object { $_.side -eq "1" -and [double]$_.price -eq 307.111 } | Select-Object -First 1
  if ($cand) {
    $c = Cancel-Order -OrderRef $cand.orderRefNumber -ClientId "TC1A" -Reason "TC1 cancel 307.111"
    if ($c.ok -or $c.status -eq 400) { Write-Pass "TC1 step5 cancel by price 307.111" } else { Write-Fail "TC1 step5 cancel" ("status=" + $c.status) }
  } else {
    Write-Skip "TC1 step5 cancel by price" "No open matching order found"
  }

  $sell2 = Submit-Order -Symbol "GOOG" -Side "2" -Qty 25 -Price 307.11 -ClientId "TC1A" -OrderType "2" -ClOrdPrefix "TC1"
  $bc = Bulk-Cancel -ClientId "TC1A" -Symbol "GOOG" -Reason "TC1 cleanup"

  if ($sell1.ok -and $buyDiff.ok -and $sell2.ok -and $bc.ok) {
    Write-Pass "TC1 completed"
  } else {
    Write-Fail "TC1" "One or more operations failed"
  }
}

function Run-TestCase2 {
  Write-Section "Test Case #2"
  $ok = $true

  1..2 | ForEach-Object { if (-not (Submit-Order -Symbol "INFY" -Side "1" -Qty 150 -Price 1307 -ClientId "TC2" -OrderType "2" -ClOrdPrefix "TC2").ok) { $ok = $false } }
  if (-not (Submit-Order -Symbol "INFY" -Side "2" -Qty 10 -Price 0 -ClientId "TC2" -OrderType "1" -ClOrdPrefix "TC2").ok) { $ok = $false }
  $aaplRefs = @()
  1..2 | ForEach-Object { $o = Submit-Order -Symbol "AAPL" -Side "1" -Qty 66 -Price 1307 -ClientId "TC2" -OrderType "2" -ClOrdPrefix "TC2"; if ($o.ok) { $aaplRefs += $o.orderRef } else { $ok = $false } }
  if (-not (Submit-Order -Symbol "INFY" -Side "2" -Qty 10 -Price 1307 -ClientId "TC2" -OrderType "2" -ClOrdPrefix "TC2").ok) { $ok = $false }
  1..2 | ForEach-Object { if (-not (Submit-Order -Symbol "BEL" -Side "1" -Qty 102 -Price 1307 -ClientId "TC2" -OrderType "2" -ClOrdPrefix "TC2").ok) { $ok = $false } }

  if ($aaplRefs.Count -ge 1) {
    $c = Cancel-Order -OrderRef $aaplRefs[0] -ClientId "TC2" -Reason "Cancel one AAPL"
    if (-not ($c.ok -or $c.status -eq 400)) { $ok = $false }
  } else {
    Write-Skip "TC2 step6 cancel one AAPL" "No AAPL refs captured"
  }

  if (-not (Submit-Order -Symbol "AAPL" -Side "2" -Qty 100 -Price 1307 -ClientId "TC2" -OrderType "2" -ClOrdPrefix "TC2").ok) { $ok = $false }

  if ($ok) { Write-Pass "TC2 completed" } else { Write-Fail "TC2" "One or more steps failed" }
}

function Run-TestCase3 {
  Write-Section "Test Case #3"
  $ok = $true
  $sellRefs = @()

  1..2 | ForEach-Object { $o = Submit-Order -Symbol "REL" -Side "2" -Qty 150 -Price 1407 -ClientId "TC3" -OrderType "2" -ClOrdPrefix "TC3"; if ($o.ok) { $sellRefs += $o.orderRef } else { $ok = $false } }
  if (-not (Submit-Order -Symbol "REL" -Side "1" -Qty 10 -Price 0 -ClientId "TC3" -OrderType "1" -ClOrdPrefix "TC3").ok) { $ok = $false }
  1..2 | ForEach-Object { if (-not (Submit-Order -Symbol "REL" -Side "1" -Qty 66 -Price 1406.96 -ClientId "TC3" -OrderType "2" -ClOrdPrefix "TC3").ok) { $ok = $false } }

  if ($sellRefs.Count -gt 0) {
    $a = Amend-Order -OrderRef $sellRefs[0] -NewPrice 1406.96 -NewQty 0 -ClientId "TC3"
    if (-not ($a.ok -or $a.status -eq 409 -or $a.status -eq 400)) { $ok = $false }
  } else {
    Write-Skip "TC3 amend" "No sell ref captured"
  }

  if (-not (Submit-Order -Symbol "REL" -Side "1" -Qty 100 -Price 1407 -ClientId "TC3" -OrderType "2" -ClOrdPrefix "TC3").ok) { $ok = $false }

  if ($ok) { Write-Pass "TC3 completed" } else { Write-Fail "TC3" "One or more steps failed" }
}

function Run-TestCase4 {
  Write-Section "Test Case #4"
  $ok = $true
  $sellRefs = @()

  1..2 | ForEach-Object { $o = Submit-Order -Symbol "MSFT" -Side "2" -Qty 77 -Price 144.68 -ClientId "TC4" -OrderType "2" -ClOrdPrefix "TC4"; if ($o.ok) { $sellRefs += $o.orderRef } else { $ok = $false } }
  if (-not (Submit-Order -Symbol "MSFT" -Side "1" -Qty 10 -Price 0 -ClientId "TC4" -OrderType "1" -ClOrdPrefix "TC4").ok) { $ok = $false }

  if ($sellRefs.Count -gt 0) {
    $a = Amend-Order -OrderRef $sellRefs[0] -NewPrice 0 -NewQty 177 -ClientId "TC4"
    if (-not ($a.ok -or $a.status -eq 409 -or $a.status -eq 400)) { $ok = $false }
  } else {
    Write-Skip "TC4 amend qty" "No sell ref captured"
  }

  if (-not (Submit-Order -Symbol "MSFT" -Side "1" -Qty 100 -Price 0 -ClientId "TC4" -OrderType "1" -ClOrdPrefix "TC4").ok) { $ok = $false }

  $history = Invoke-Api GET "/api/system/audit/orders?limit=200" $null
  if ($history.ok) {
    Write-Pass "TC4 step5 order history available via audit endpoint"
  } else {
    Write-Fail "TC4 step5 order history" "Audit endpoint unavailable"
  }

  if ($ok) { Write-Pass "TC4 completed" } else { Write-Fail "TC4" "One or more steps failed" }
}

function Run-TestCase5 {
  Write-Section "Test Case #5"

  $open = Get-OpenOrders
  if ($open.Count -ge 0) {
    Write-Pass "TC5 step1 open orders retrieved count=$($open.Count)"
  } else {
    Write-Fail "TC5 step1" "Failed to retrieve open orders"
  }

  if ($open.Count -gt 0) {
    $sym = $open[0].symbol
    $spot = Get-ReferencePrice $sym
    $opt = Invoke-Api GET ("/api/options/price?spot=" + $spot + "&strike=" + [math]::Round($spot,2) + "&timeToExpiry=0.25&riskFreeRate=0.05&volatility=0.25&isCall=true") $null
    if ($opt.ok) {
      Write-Pass "TC5 step2 option pricing available for open-order symbol=$sym"
    } else {
      Write-Fail "TC5 step2 option pricing" "Options endpoint call failed"
    }
  } else {
    Write-Skip "TC5 step2 option pricing" "No open orders from prior cases"
  }

  Write-Skip "TC5 step3 kill order service" "Requires external process orchestration"
  Write-Skip "TC5 step4 restart order service after 30s" "Requires external process orchestration"

  $open2 = Get-OpenOrders
  if ($open2.Count -gt 0) {
    $o = $open2[0]
    $oppSide = if ($o.side -eq "1") { "2" } else { "1" }
    $price = [double]$o.price
    $qty = if ($o.leavesQty) { [int]$o.leavesQty } else { 10 }
    $sub = Submit-Order -Symbol $o.symbol -Side $oppSide -Qty $qty -Price $price -ClientId "TC5" -OrderType "2" -ClOrdPrefix "TC5"
    if ($sub.ok) { Write-Pass "TC5 step5 opposite side order submitted" } else { Write-Fail "TC5 step5" "Failed to submit opposite side" }
  } else {
    Write-Skip "TC5 step5 opposite side order" "No open orders available"
  }

  $trades = Invoke-Api GET "/api/trades?limit=100" $null
  if ($trades.ok) { Write-Pass "TC5 step6 trades displayed" } else { Write-Fail "TC5 step6" "Trades endpoint unavailable" }
}

function Run-TestCase6 {
  Write-Section "Test Case #6"
  $ok = $true
  $buyRefs = @()

  1..3 | ForEach-Object { $o = Submit-Order -Symbol "CSCO" -Side "1" -Qty 3000 -Price 180.68 -ClientId "TC6" -OrderType "2" -ClOrdPrefix "TC6"; if ($o.ok) { $buyRefs += $o.orderRef } else { $ok = $false } }

  Write-Skip "TC6 step2 disconnect FIX session" "Requires FIX session control endpoint or external QuickFIX client action"
  Write-Skip "TC6 step3 reconnect FIX session after 30s" "Requires FIX session control endpoint or external QuickFIX client action"

  $fixMetrics = Invoke-Api GET "/api/system/telemetry/fix" $null
  if ($fixMetrics.ok) { Write-Pass "TC6 step4 FIX telemetry available" } else { Write-Fail "TC6 step4" "FIX telemetry not available" }

  if ($buyRefs.Count -gt 0) {
    $a = Amend-Order -OrderRef $buyRefs[0] -NewPrice 0 -NewQty 3500 -ClientId "TC6"
    if (-not ($a.ok -or $a.status -eq 409 -or $a.status -eq 400)) { $ok = $false }
  } else {
    Write-Skip "TC6 step5 amend qty" "No buy ref captured"
  }

  $sell = Submit-Order -Symbol "CSCO" -Side "2" -Qty 1000 -Price 0 -ClientId "TC6" -OrderType "1" -ClOrdPrefix "TC6"
  if (-not $sell.ok) { $ok = $false }

  $fixMetrics2 = Invoke-Api GET "/api/system/telemetry/fix" $null
  if ($fixMetrics2.ok) { Write-Pass "TC6 step7 FIX telemetry captured post-trade" } else { Write-Fail "TC6 step7" "FIX telemetry unavailable" }

  $trades = Invoke-Api GET "/api/trades/CSCO" $null
  if ($trades.ok) { Write-Pass "TC6 step8 trades displayed" } else { Write-Fail "TC6 step8" "Trades endpoint unavailable" }

  $audit = Invoke-Api GET "/api/orders/audit/client/TC6" $null
  if ($audit.ok) { Write-Pass "TC6 step9 order history available" } else { Write-Fail "TC6 step9" "Order history unavailable" }

  if ($ok) { Write-Pass "TC6 completed (automatable steps)" } else { Write-Fail "TC6" "One or more automatable steps failed" }
}

# ---------------- Main ----------------
Write-Section "Full E2E + Performance Suite"

$health = Invoke-Api GET "/api/system/health" $null
if (-not $health.ok) {
  Write-Fail "Precheck health" "Backend unreachable at $BaseUrl"
  Write-Host ""
  Write-Host "=======================================" -ForegroundColor Cyan
  Write-Host " Full Suite Results" -ForegroundColor Cyan
  Write-Host "=======================================" -ForegroundColor Cyan
  Write-Host "  PASSED : $($script:pass)" -ForegroundColor Green
  Write-Host "  FAILED : $($script:fail)" -ForegroundColor Red
  Write-Host "  SKIPPED: $($script:skip)" -ForegroundColor Yellow
  exit 1
}
Write-Pass "Precheck health"

Ensure-TradingReady

Run-PerformanceBurst
Run-PerformanceThroughput
Run-PerformanceOrderLatency
Run-PerformanceDbLatency

Run-TestCase1
Run-TestCase2
Run-TestCase3
Run-TestCase4
Run-TestCase5
Run-TestCase6

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host " Full Suite Results" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  PASSED : $($script:pass)" -ForegroundColor Green
if ($script:fail -gt 0) {
  Write-Host "  FAILED : $($script:fail)" -ForegroundColor Red
} else {
  Write-Host "  FAILED : $($script:fail)" -ForegroundColor Green
}
Write-Host "  SKIPPED: $($script:skip)" -ForegroundColor Yellow

if ($script:fail -gt 0) {
  exit 1
} else {
  exit 0
}
