param(
  [string]$FrontendUrl = 'http://127.0.0.1:5173',
  [string]$BackendUrl = 'http://127.0.0.1:8080'
)

$ErrorActionPreference = 'Stop'
$FrontendUrl = $FrontendUrl.TrimEnd('/')
$BackendUrl = $BackendUrl.TrimEnd('/')
$suffix = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
$factoryId = $null
$needId = $null
$vehicleId = $null
$poiId = $null
$actionId = [int]([DateTime]::UtcNow.ToString('HHmmss')) + 100000
$simulationStarted = $false

function Invoke-Api {
  param([string]$Path, [string]$Method = 'GET', [object]$Body = $null, [string]$Via = 'frontend')
  $base = if ($Via -eq 'backend') { $BackendUrl } else { $FrontendUrl }
  $params = @{ Uri = "$base$Path"; Method = $Method; TimeoutSec = 15 }
  if ($null -ne $Body) {
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
  }
  Invoke-RestMethod @params
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-HttpConflict {
  param([string]$Path, [object]$Body)
  try {
    Invoke-Api -Path $Path -Method 'PUT' -Body $Body | Out-Null
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -eq 409) { Write-Host 'PASS stale version rejected with HTTP 409'; return }
    throw "Expected HTTP 409 for stale version, got $status. $($_.Exception.Message)"
  }
  throw 'Expected HTTP 409 for stale version, but the request succeeded.'
}

function Pass { param([string]$Message) Write-Host "PASS $Message" -ForegroundColor Green }

try {
  foreach ($path in @('/factories', '/needs', '/vehicles/active', '/pois', '/actions')) {
    $null = Invoke-Api -Path $path
  }
  Pass 'frontend Vite proxy reaches all five list APIs'

  $factoryName = "联调工厂-$suffix"
  Invoke-Api -Path '/factories' -Method POST -Body @{
    factoryName = $factoryName; address = '自动化联调数据'; factoryLatitude = 30.5728; factoryLongitude = 104.0668
  } | Out-Null
  $factoryRows = Invoke-Api -Path '/factories'
  $factoryId = [int]($factoryRows | Where-Object { $_.factoryName -eq $factoryName } | Select-Object -ExpandProperty id -First 1)
  Assert-True ($factoryId -gt 0) 'Factory was not returned by GET /factories.'
  Invoke-Api -Path '/factories' -Method PUT -Body @{
    id = $factoryId; factoryName = "$factoryName-已更新"; address = '自动化联调数据'; factoryLatitude = 30.5728; factoryLongitude = 104.0668
  } | Out-Null
  Invoke-Api -Path "/factories/$factoryId/generate-need?material=$([uri]::EscapeDataString("工厂自动需求-$suffix"))" -Method POST | Out-Null
  Pass 'factory create, update, and generate-need APIs'

  $needName = "联调货物-$suffix"
  Invoke-Api -Path '/needs' -Method POST -Body @{
    needContent = $needName; factoryId = $factoryId; cargoTotalWeight = 10; requiredVehicleType = 'TRUCK'
  } | Out-Null
  $needRows = Invoke-Api -Path '/needs'
  $needId = [int]($needRows | Where-Object { $_.needContent -eq $needName } | Select-Object -ExpandProperty id -First 1)
  Assert-True ($needId -gt 0) 'Need was not returned by GET /needs.'
  $need = Invoke-Api -Path "/needs/$needId"
  Assert-True ([decimal]$need.cargoTotalWeight -eq 10) 'Need weight was not persisted.'
  Assert-True ($need.requiredVehicleType -eq 'TRUCK') 'Required vehicle type was not persisted.'
  Pass 'need create and database persistence'

  $license = "T$suffix"
  Invoke-Api -Path '/vehicles' -Method POST -Body @{
    typeCode = 'TRUCK'; maxLoad = '20'; licenseNumber = $license; currentLatitude = 30.60; currentLongitude = 104.11; currentAction = 'AVAILABLE'
  } | Out-Null
  $vehicleRows = Invoke-Api -Path '/vehicles/active'
  $vehicleId = [int]($vehicleRows | Where-Object { $_.licenseNumber -eq $license } | Select-Object -ExpandProperty id -First 1)
  Assert-True ($vehicleId -gt 0) 'Vehicle was not returned by GET /vehicles/active.'
  $vehicle = Invoke-Api -Path "/vehicles/$vehicleId"
  Assert-True ([decimal]$vehicle.maxLoad -eq 20) 'Vehicle maximum load was not persisted.'
  Pass 'vehicle create and database persistence'

  $match = Invoke-Api -Path "/matching/score?needId=$needId&vehicleId=$vehicleId"
  Assert-True ([bool]$match.eligible) "Matching rejected the test pair: $($match.reasons -join ', ')"
  $task = Invoke-Api -Path '/tasks' -Method POST -Body @{
    taskName = "联调任务-$suffix"; needId = $needId; vehicleId = $vehicleId; matchScore = $match.score
  }
  Assert-True ($task.status -eq 'ASSIGNED') 'New task was not marked ASSIGNED.'
  Pass 'matching and task assignment'

  $tick = Invoke-Api -Path '/simulation/step' -Method POST
  Assert-True ([int]$tick.movedVehicles -ge 1) 'Simulation step did not move the assigned vehicle.'
  $vehicle = Invoke-Api -Path "/vehicles/$vehicleId"
  Assert-True ([long]$vehicle.version -ge 1) 'Simulation did not increment vehicle version.'
  Assert-True ([math]::Abs([double]$vehicle.currentLatitude - 30.60) -gt 0.000001) 'Simulation did not persist the vehicle position.'

  $oldVersion = [long]$vehicle.version
  $vehicle = Invoke-Api -Path "/vehicles/$vehicleId/state" -Method PUT -Body @{ version = $oldVersion; status = 'LOADING' }
  Assert-True ($vehicle.status -eq 'LOADING') 'Vehicle state transition was not saved.'
  Assert-HttpConflict -Path "/vehicles/$vehicleId/state" -Body @{ version = $oldVersion; status = 'TRANSPORTING' }
  $vehicle = Invoke-Api -Path "/vehicles/$vehicleId/position" -Method PUT -Body @{
    version = [long]$vehicle.version; latitude = 30.55; longitude = 104.08; observedAt = [DateTime]::UtcNow.ToString('o')
  }
  Assert-True ([math]::Abs([double]$vehicle.currentLatitude - 30.55) -lt 0.000001) 'Vehicle position update was not saved.'
  Pass 'simulation, position persistence, state transition, and stale-version conflict'

  $revenue = Invoke-Api -Path "/tasks/$($task.id)/revenue?distanceKm=10&pricePerTonKm=10&fuelCostPerKm=2&accidentLossRate=0.05"
  Assert-True ([math]::Abs([double]$revenue.transportRevenue - 1000) -lt 0.001) 'Unexpected transport revenue.'
  Assert-True ([math]::Abs([double]$revenue.netRevenue - 930) -lt 0.001) 'Unexpected net revenue.'
  Pass 'task revenue calculation'

  $poi = Invoke-Api -Path '/pois' -Method POST -Body @{
    poiName = "联调加油站-$suffix"; poiType = '加油站'; poiAddress = '自动化联调数据'; poiLatitude = 30.58; poiLongitude = 104.09
  }
  $poiId = [int]$poi.id
  $poiRows = @(Invoke-Api -Path '/pois')
  Assert-True (@($poiRows | Where-Object { [int]$_.id -eq $poiId }).Count -eq 1) 'Created POI is missing from GET /pois.'
  Pass 'POI create and list APIs'

  Invoke-Api -Path '/actions' -Method POST -Body @{
    id = $actionId; actionName = "联调装货-$suffix"; actionType = 'LOADING'; duration = 120; accidentRate = 0.01
  } | Out-Null
  $action = Invoke-Api -Path "/actions/$actionId"
  Assert-True ($action.actionName -eq "联调装货-$suffix") 'Action create/read failed.'
  Invoke-Api -Path '/actions' -Method PUT -Body @{
    id = $actionId; actionName = "联调装货-更新-$suffix"; actionType = 'LOADING'; duration = 180; accidentRate = 0.02
  } | Out-Null
  $action = Invoke-Api -Path "/actions/$actionId"
  Assert-True ($action.duration -eq 180) 'Action update failed.'
  Invoke-Api -Path "/actions/$actionId" -Method DELETE | Out-Null
  Pass 'action definition create, update, read, and delete APIs'

  Invoke-Api -Path '/simulation/start' -Method POST | Out-Null
  $simulationStarted = $true
  Start-Sleep -Milliseconds 1200
  $running = Invoke-Api -Path '/simulation/status'
  Assert-True ([bool]$running.running) 'Simulation did not enter running state.'
  Invoke-Api -Path '/simulation/pause' -Method POST | Out-Null
  $simulationStarted = $false
  Pass 'simulation start, status polling, and pause APIs'

  Invoke-Api -Path "/pois/$poiId" -Method DELETE | Out-Null
  Invoke-Api -Path "/needs/$needId" -Method DELETE | Out-Null
  Invoke-Api -Path "/vehicles/$vehicleId/deactivate" -Method DELETE | Out-Null
  Invoke-Api -Path "/factories/$factoryId" -Method DELETE | Out-Null
  Pass 'soft-deactivation APIs for POI, need, vehicle, and factory'

  Write-Host "联调完成。任务 ID=$($task.id)，测试名称后缀=$suffix。" -ForegroundColor Cyan
} finally {
  if ($simulationStarted) { try { Invoke-Api -Path '/simulation/pause' -Method POST | Out-Null } catch {} }
}
