<script setup>
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'
import MapView from './components/MapView.vue'
import { api } from './api.js'

const mapView = ref(null)
const loading = ref(false)
const error = ref('')
const notice = ref('')
const lastRefresh = ref('尚未刷新')
const factories = ref([])
const needs = ref([])
const vehicles = ref([])
const pois = ref([])
const actions = ref([])
const matching = ref(null)
const revenue = ref(null)
const selectedNeedId = ref('')
const selectedVehicleId = ref('')
const selectedTaskId = ref('')
const selectedFactoryId = ref('')
const selectedPoiId = ref('')
const selectedActionId = ref('')
const stateTarget = ref('LOADING')
const simulationRunning = ref(false)
const simulationTick = ref(0)
const simulationTimer = ref(null)
const simulationBusy = ref(false)
const simulationStatus = ref({ running: false, ticks: 0, movedVehicles: 0, lastError: null })

const factoryForm = reactive({ factoryName: '', address: '', factoryLatitude: 30.5728, factoryLongitude: 104.0668 })
const needForm = reactive({ needContent: '', factoryId: '', cargoId: '', cargoTotalWeight: 10, requiredVehicleType: '' })
const vehicleForm = reactive({ typeCode: 'TRUCK', maxLoad: '20', licenseNumber: '', currentLatitude: 30.5728, currentLongitude: 104.0668, currentAction: 'AVAILABLE' })
const poiForm = reactive({ poiName: '', poiType: '停车场', poiAddress: '', poiLatitude: 30.5728, poiLongitude: 104.0668 })
const revenueForm = reactive({ distanceKm: '10', pricePerTonKm: '10', fuelCostPerKm: '2', accidentLossRate: '0' })
const positionForm = reactive({ latitude: '', longitude: '' })
const actionForm = reactive({ id: '', actionName: '', actionType: '', duration: 60, accidentRate: 0.01 })
const factoryMaterial = ref('演示原材料')
const selectedNeed = computed(() => needs.value.find((item) => Number(item.id) === Number(selectedNeedId.value)))
const selectedVehicle = computed(() => vehicles.value.find((item) => Number(item.id) === Number(selectedVehicleId.value)))
const selectedFactory = computed(() => factories.value.find((item) => Number(item.id) === Number(selectedFactoryId.value)))
const stateOptions = computed(() => {
  switch (String(selectedVehicle.value?.status || '').toUpperCase()) {
    case 'ASSIGNED': return ['LOADING']
    case 'LOADING': return ['TRANSPORTING']
    case 'TRANSPORTING': return ['UNLOADING']
    case 'UNLOADING': return ['AVAILABLE']
    case 'AVAILABLE': return ['RESTING', 'MAINTENANCE']
    case 'RESTING': case 'MAINTENANCE': return ['AVAILABLE']
    default: return []
  }
})
watch(stateOptions, (options) => {
  if (!options.includes(stateTarget.value)) stateTarget.value = options[0] || ''
}, { immediate: true })

function clearMessage() { error.value = ''; notice.value = '' }
function showError(reason) { error.value = reason instanceof Error ? reason.message : String(reason); notice.value = '' }
function showNotice(message) { notice.value = message; error.value = '' }

async function refreshAll(silent = false) {
  loading.value = true
  clearMessage()
  try {
    const results = await Promise.allSettled([api.listFactories(), api.listNeeds(), api.listVehicles(), api.listPois(), api.listActions()])
    const [factoryResult, needResult, vehicleResult, poiResult, actionResult] = results
    if (factoryResult.status === 'fulfilled') factories.value = factoryResult.value || []
    if (needResult.status === 'fulfilled') needs.value = needResult.value || []
    if (vehicleResult.status === 'fulfilled') vehicles.value = vehicleResult.value || []
    if (poiResult.status === 'fulfilled') pois.value = poiResult.value || []
    if (actionResult.status === 'fulfilled') actions.value = actionResult.value || []
    const failed = results.find((item) => item.status === 'rejected')
    if (failed) throw failed.reason
    lastRefresh.value = new Date().toLocaleTimeString()
    if (!silent) showNotice(`已刷新：工厂 ${factories.value.length}，需求 ${needs.value.length}，车辆 ${vehicles.value.length}，POI ${pois.value.length}，行为定义 ${actions.value.length}`)
  } catch (reason) { showError(reason) } finally { loading.value = false }
}

async function refreshSimulationStatus() {
  try {
    simulationStatus.value = await api.simulationStatus()
    simulationRunning.value = simulationStatus.value.running
    simulationTick.value = simulationStatus.value.ticks
  } catch (reason) { showError(reason) }
}

async function pollSimulation() {
  if (simulationBusy.value) return
  simulationBusy.value = true
  try {
    simulationStatus.value = await api.simulationStatus()
    simulationRunning.value = simulationStatus.value.running
    simulationTick.value = simulationStatus.value.ticks
    vehicles.value = await api.listVehicles()
    if (!simulationRunning.value && simulationTimer.value) {
      window.clearInterval(simulationTimer.value)
      simulationTimer.value = null
    }
    if (simulationStatus.value.lastError) showError(simulationStatus.value.lastError)
  } catch (reason) { showError(reason) } finally { simulationBusy.value = false }
}

async function createFactory() {
  try {
    const created = await api.createFactory({ ...factoryForm })
    showNotice(`工厂已创建${created?.id ? `（ID ${created.id}）` : ''}`)
    await refreshAll()
  } catch (reason) { showError(reason) }
}

function loadSelectedFactory() {
  if (!selectedFactory.value) return showError('请选择工厂')
  Object.assign(factoryForm, {
    factoryName: selectedFactory.value.factoryName || '',
    address: selectedFactory.value.address || '',
    factoryLatitude: Number(selectedFactory.value.factoryLatitude),
    factoryLongitude: Number(selectedFactory.value.factoryLongitude),
  })
  showNotice('工厂资料已载入上方表单；修改后点击“保存工厂修改”')
}

async function updateSelectedFactory() {
  if (!selectedFactory.value) return showError('请选择工厂')
  try {
    await api.updateFactory({ id: Number(selectedFactoryId.value), ...factoryForm })
    showNotice('工厂已更新')
    await refreshAll(true)
  } catch (reason) { showError(reason) }
}

async function generateNeedFromFactory() {
  if (!selectedFactory.value) return showError('请先选择工厂')
  if (!factoryMaterial.value.trim()) return showError('请输入需求物料名称')
  try {
    await api.generateNeedFromFactory(Number(selectedFactoryId.value), factoryMaterial.value.trim())
    showNotice('已通过工厂接口生成一条 1 吨需求')
    await refreshAll(true)
  } catch (reason) { showError(reason) }
}

async function createNeed() {
  if (!needForm.factoryId) return showError('请先选择需求所属工厂')
  try {
    await api.createNeed({ needContent: needForm.needContent || '演示运输需求', factoryId: Number(needForm.factoryId), cargoId: needForm.cargoId ? Number(needForm.cargoId) : null, cargoTotalWeight: Number(needForm.cargoTotalWeight), requiredVehicleType: needForm.requiredVehicleType || null })
    showNotice('需求已创建')
    await refreshAll()
  } catch (reason) { showError(reason) }
}

async function createVehicle() {
  try {
    await api.createVehicle({ ...vehicleForm, currentLatitude: Number(vehicleForm.currentLatitude), currentLongitude: Number(vehicleForm.currentLongitude) })
    showNotice('车辆已创建')
    await refreshAll()
  } catch (reason) { showError(reason) }
}

async function createPoi() {
  try {
    await api.createPoi({ ...poiForm, poiLatitude: Number(poiForm.poiLatitude), poiLongitude: Number(poiForm.poiLongitude) })
    showNotice('地图 POI 已创建')
    await refreshAll()
  } catch (reason) { showError(reason) }
}

function loadSelectedAction() {
  const action = actions.value.find((item) => String(item.id) === String(selectedActionId.value))
  if (!action) return showError('请选择动作定义')
  Object.assign(actionForm, { id: action.id, actionName: action.actionName || '', actionType: action.actionType || '', duration: action.duration ?? 60, accidentRate: action.accidentRate ?? 0 })
}

async function saveAction(isUpdate = false) {
  if (!actionForm.id || !actionForm.actionName.trim()) return showError('动作编号和名称不能为空')
  const payload = { ...actionForm, id: Number(actionForm.id), duration: Number(actionForm.duration), accidentRate: Number(actionForm.accidentRate) }
  try {
    if (isUpdate) await api.updateAction(payload)
    else await api.createAction(payload)
    showNotice(isUpdate ? '动作定义已更新' : '动作定义已新增')
    await refreshAll(true)
  } catch (reason) { showError(reason) }
}

async function deleteSelectedAction() {
  if (!selectedActionId.value) return showError('请选择动作定义')
  if (!window.confirm('确定物理删除此动作定义？')) return
  try {
    await api.deleteAction(Number(selectedActionId.value))
    selectedActionId.value = ''
    showNotice('动作定义已删除')
    await refreshAll(true)
  } catch (reason) { showError(reason) }
}

async function deactivateSelectedFactory() {
  if (!selectedFactoryId.value) return showError('请选择工厂')
  if (!window.confirm('将工厂设为失效？历史记录会保留。')) return
  try { await api.deactivateFactory(Number(selectedFactoryId.value)); showNotice('工厂已失效'); await refreshAll() }
  catch (reason) { showError(reason) }
}

async function deactivateSelectedNeed() {
  if (!selectedNeedId.value) return showError('请选择需求')
  if (!window.confirm('将需求设为失效？')) return
  try { await api.deactivateNeed(Number(selectedNeedId.value)); showNotice('需求已失效'); await refreshAll() }
  catch (reason) { showError(reason) }
}

async function deactivateSelectedVehicle() {
  if (!selectedVehicleId.value) return showError('请选择车辆')
  if (!window.confirm('将车辆设为失效？历史记录会保留。')) return
  try { await api.deactivateVehicle(Number(selectedVehicleId.value)); showNotice('车辆已失效'); await refreshAll() }
  catch (reason) { showError(reason) }
}

async function deactivateSelectedPoi() {
  if (!selectedPoiId.value) return showError('请选择 POI')
  if (!window.confirm('将 POI 设为失效？被路线引用时后端会拒绝。')) return
  try { await api.deactivatePoi(Number(selectedPoiId.value)); showNotice('POI 已失效'); await refreshAll() }
  catch (reason) { showError(reason) }
}

async function searchFactories() {
  clearMessage()
  try {
    const results = await mapView.value?.searchFactories()
    if (!results?.length) return showError('高德没有返回工厂 POI，请检查地图密钥、城市和网络')
    const unique = new Map()
    results.forEach((poi) => {
      if (!poi.location) return
      const key = `${poi.name}|${poi.location.lng.toFixed(6)}|${poi.location.lat.toFixed(6)}`
      unique.set(key, poi)
    })
    let created = 0
    for (const poi of unique.values()) {
      try {
        await api.createFactory({ factoryName: poi.name, address: typeof poi.address === 'string' ? poi.address : '', factoryLatitude: poi.location.lat, factoryLongitude: poi.location.lng })
        created += 1
      } catch (reason) { console.warn('工厂 POI 写入失败', poi.name, reason) }
    }
    showNotice(`搜索 ${unique.size} 个 POI，成功写入 ${created} 个。后续应增加数据库去重约束。`)
    await refreshAll()
  } catch (reason) { showError(reason) }
}

async function scoreSelected() {
  matching.value = null
  if (!selectedNeedId.value || !selectedVehicleId.value) return showError('请选择需求和车辆')
  try {
    matching.value = await api.scoreMatching(Number(selectedNeedId.value), Number(selectedVehicleId.value))
    showNotice(matching.value.eligible ? `匹配通过，得分 ${matching.value.score}` : '匹配未通过，请查看原因')
    return matching.value
  } catch (reason) { showError(reason) }
}

async function assignTask() {
  const match = await scoreSelected()
  if (!match?.eligible) return
  try {
    const task = await api.createTask({ taskName: `运输任务-${selectedNeedId.value}`, needId: Number(selectedNeedId.value), vehicleId: Number(selectedVehicleId.value), matchScore: match.score })
    if (task?.id) selectedTaskId.value = task.id
    showNotice(`任务已创建${task?.id ? `（ID ${task.id}）` : ''}`)
    await refreshAll()
  } catch (reason) { showError(reason) }
}

async function updateState() {
  const vehicle = selectedVehicle.value
  if (!vehicle) return showError('请选择车辆')
  if (vehicle.version === null || vehicle.version === undefined) return showError('当前车辆没有版本号，请先完成数据库扩展迁移')
  try {
    const updated = await api.updateVehicleState(vehicle.id, { version: vehicle.version, status: stateTarget.value })
    vehicles.value = vehicles.value.map((item) => item.id === updated.id ? updated : item)
    showNotice(`车辆状态已更新为 ${updated.status}`)
  } catch (reason) { showError(reason) }
}

async function updatePosition() {
  const vehicle = selectedVehicle.value
  if (!vehicle) return showError('请选择车辆')
  if (vehicle.version === null || vehicle.version === undefined) return showError('当前车辆没有版本号，请先完成数据库扩展迁移')
  const latitude = Number(positionForm.latitude), longitude = Number(positionForm.longitude)
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return showError('请输入有效经纬度')
  try {
    const updated = await api.updateVehiclePosition(vehicle.id, { version: vehicle.version, latitude, longitude, observedAt: new Date().toISOString() })
    vehicles.value = vehicles.value.map((item) => item.id === updated.id ? updated : item)
    showNotice(`车辆 ${vehicle.id} 的位置已更新`)
  } catch (reason) { showError(reason) }
}

async function calculateRevenue() {
  if (!selectedTaskId.value) return showError('请输入任务 ID')
  try { revenue.value = await api.getRevenue(Number(selectedTaskId.value), { distanceKm: revenueForm.distanceKm, pricePerTonKm: revenueForm.pricePerTonKm, fuelCostPerKm: revenueForm.fuelCostPerKm, accidentLossRate: revenueForm.accidentLossRate }); showNotice('收益已计算') }
  catch (reason) { showError(reason) }
}

async function stepSimulation() {
  try {
    simulationStatus.value = await api.stepSimulation()
    simulationRunning.value = simulationStatus.value.running
    simulationTick.value = simulationStatus.value.ticks
    vehicles.value = await api.listVehicles()
    showNotice(`后端仿真单步完成：推进 ${simulationStatus.value.movedVehicles} 辆车`)
  } catch (reason) { showError(reason) }
}

async function startSimulation() {
  if (simulationRunning.value) return
  try {
    simulationStatus.value = await api.startSimulation()
    simulationRunning.value = simulationStatus.value.running
    simulationTick.value = simulationStatus.value.ticks
    if (!simulationTimer.value) simulationTimer.value = window.setInterval(pollSimulation, 1000)
    showNotice('后端仿真循环已启动：每秒推进已派单车辆并保存位置')
  } catch (reason) { showError(reason) }
}

function stopSimulationPolling() {
  if (simulationTimer.value) window.clearInterval(simulationTimer.value)
  simulationTimer.value = null
}

async function pauseSimulation() {
  try {
    simulationStatus.value = await api.pauseSimulation()
    simulationRunning.value = simulationStatus.value.running
    simulationTick.value = simulationStatus.value.ticks
    stopSimulationPolling()
    await refreshAll(true)
    showNotice('后端仿真循环已暂停')
  } catch (reason) { showError(reason) }
}

onMounted(async () => { await refreshAll(); await refreshSimulationStatus() })
onUnmounted(stopSimulationPolling)
</script>

<template>
  <div class="app-shell">
    <MapView ref="mapView" :factories="factories" :pois="pois" :vehicles="vehicles" />
    <aside class="control-panel">
      <header class="panel-header">
        <div><p class="eyebrow">TRANSPORT SIMULATION</p><h1>运输车辆调度控制台</h1><p class="muted">后端：traffic backend · 刷新：{{ lastRefresh }}</p></div>
        <button class="icon-button" title="刷新数据" :disabled="loading" @click="refreshAll">↻</button>
      </header>
      <div v-if="error" class="message error">{{ error }}</div><div v-if="notice" class="message success">{{ notice }}</div>

      <section class="panel-section"><div class="section-title"><h2>地图与数据</h2><span>{{ factories.length }} 工厂 · {{ vehicles.length }} 车</span></div><div class="button-row"><button class="primary" @click="searchFactories">搜索并导入工厂</button><button @click="refreshAll">重新读取</button></div><p class="hint">只有点击按钮才会写入 POI；导入时会先在本次结果中去重。</p></section>

      <section class="panel-section"><div class="section-title"><h2>新增工厂</h2></div><div class="form-grid"><input v-model="factoryForm.factoryName" placeholder="工厂名称" /><input v-model="factoryForm.address" placeholder="地址" /><input v-model.number="factoryForm.factoryLatitude" type="number" step="0.000001" placeholder="纬度" /><input v-model.number="factoryForm.factoryLongitude" type="number" step="0.000001" placeholder="经度" /></div><button class="form-action" @click="createFactory">保存工厂</button></section>
      <section class="panel-section"><div class="section-title"><h2>工厂维护</h2></div><div class="form-grid"><select v-model="selectedFactoryId"><option value="">选择工厂</option><option v-for="factory in factories" :key="factory.id" :value="factory.id">{{ factory.id }} · {{ factory.factoryName }}</option></select><button @click="loadSelectedFactory">载入编辑</button><button @click="updateSelectedFactory">保存工厂修改</button><button @click="deactivateSelectedFactory">工厂失效</button></div><div class="button-row"><input v-model="factoryMaterial" placeholder="工厂生成需求的物料名称" /><button @click="generateNeedFromFactory">通过工厂生成需求</button></div></section>

      <section class="panel-section"><div class="section-title"><h2>新增地图 POI</h2></div><div class="form-grid"><input v-model="poiForm.poiName" placeholder="地点名称" /><select v-model="poiForm.poiType"><option>停车场</option><option>加油站</option><option>维修站</option><option>工厂</option><option>货运站</option><option>其他</option></select><input v-model="poiForm.poiAddress" placeholder="地址" /><input v-model.number="poiForm.poiLatitude" type="number" step="0.000001" placeholder="纬度" /><input v-model.number="poiForm.poiLongitude" type="number" step="0.000001" placeholder="经度" /></div><div class="button-row"><button @click="createPoi">保存 POI</button><select v-model="selectedPoiId"><option value="">选择 POI</option><option v-for="poi in pois" :key="poi.id" :value="poi.id">{{ poi.id }} · {{ poi.poiName }}</option></select><button @click="deactivateSelectedPoi">POI 失效</button></div></section>

      <section class="panel-section"><div class="section-title"><h2>动作定义</h2><span>{{ actions.length }} 项</span></div><div class="form-grid"><input v-model.number="actionForm.id" type="number" min="1" placeholder="动作编号" /><input v-model="actionForm.actionName" placeholder="动作名称" /><input v-model="actionForm.actionType" placeholder="动作类型" /><input v-model.number="actionForm.duration" type="number" min="1" placeholder="默认时长（秒）" /><input v-model.number="actionForm.accidentRate" type="number" min="0" max="1" step="0.001" placeholder="事故率 0-1" /></div><div class="button-row"><button @click="saveAction(false)">新增动作</button><select v-model="selectedActionId"><option value="">选择动作</option><option v-for="action in actions" :key="action.id" :value="action.id">{{ action.id }} · {{ action.actionName }}</option></select><button @click="loadSelectedAction">载入动作</button><button @click="saveAction(true)">保存修改</button><button @click="deleteSelectedAction">删除动作</button></div></section>

      <section class="panel-section"><div class="section-title"><h2>新增需求</h2></div><div class="form-grid"><input v-model="needForm.needContent" placeholder="需求名称 / 货物" /><select v-model="needForm.factoryId"><option value="">选择工厂</option><option v-for="factory in factories" :key="factory.id" :value="factory.id">{{ factory.id }} · {{ factory.factoryName }}</option></select><input v-model.number="needForm.cargoTotalWeight" type="number" min="0.01" step="0.01" placeholder="重量（吨）" /><input v-model="needForm.requiredVehicleType" placeholder="要求车型（可选）" /></div><div class="button-row"><button @click="createNeed">保存需求</button><button @click="deactivateSelectedNeed">选中需求失效</button></div></section>

      <section class="panel-section"><div class="section-title"><h2>新增车辆</h2></div><div class="form-grid"><input v-model="vehicleForm.licenseNumber" placeholder="车牌号" /><input v-model="vehicleForm.typeCode" placeholder="车型" /><input v-model="vehicleForm.maxLoad" placeholder="最大载重（吨）" /><input v-model.number="vehicleForm.currentLatitude" type="number" step="0.000001" placeholder="纬度" /><input v-model.number="vehicleForm.currentLongitude" type="number" step="0.000001" placeholder="经度" /></div><div class="button-row"><button @click="createVehicle">保存车辆</button><button @click="deactivateSelectedVehicle">选中车辆失效</button></div></section>

      <section class="panel-section"><div class="section-title"><h2>匹配与派单</h2></div><div class="form-grid"><select v-model="selectedNeedId"><option value="">选择需求</option><option v-for="need in needs" :key="need.id" :value="need.id">{{ need.id }} · {{ need.needContent }}</option></select><select v-model="selectedVehicleId"><option value="">选择车辆</option><option v-for="vehicle in vehicles" :key="vehicle.id" :value="vehicle.id">{{ vehicle.id }} · {{ vehicle.licenseNumber || vehicle.bandName || vehicle.typeCode }}</option></select></div><div class="button-row"><button @click="scoreSelected">计算匹配度</button><button class="primary" @click="assignTask">生成并指派任务</button></div><div v-if="matching" class="result"><strong>{{ matching.eligible ? '可指派' : '不可指派' }}</strong> · 得分 {{ matching.score }}<br /><span v-for="reason in matching.reasons" :key="reason">{{ reason }}；</span></div></section>

      <section class="panel-section"><div class="section-title"><h2>车辆位置、状态与仿真</h2><span>后端 tick {{ simulationTick }}</span></div><div class="form-grid"><input v-model.number="positionForm.latitude" type="number" step="0.000001" placeholder="纬度" /><input v-model.number="positionForm.longitude" type="number" step="0.000001" placeholder="经度" /><button @click="updatePosition">保存选中车辆位置</button><select v-model="stateTarget"><option v-for="option in stateOptions" :key="option" :value="option">{{ option }}</option></select><button :disabled="!stateOptions.length" @click="updateState">更新选中车辆状态</button></div><div class="button-row"><button class="primary" :disabled="simulationRunning" @click="startSimulation">启动后端仿真循环</button><button :disabled="!simulationRunning" @click="pauseSimulation">暂停</button><button :disabled="simulationRunning" @click="stepSimulation">后端单步</button></div><p class="hint">仿真每秒推进已派单车辆最多 2 公里，位置和版本号保存到数据库；状态按钮只显示当前状态允许的下一步。</p></section>

      <section class="panel-section"><div class="section-title"><h2>收益计算</h2></div><div class="form-grid"><input v-model="selectedTaskId" type="number" min="1" placeholder="任务 ID" /><input v-model="revenueForm.distanceKm" type="number" min="0.01" step="0.1" placeholder="距离 km" /><input v-model="revenueForm.pricePerTonKm" type="number" min="0" step="0.1" placeholder="元 / 吨·公里" /><input v-model="revenueForm.fuelCostPerKm" type="number" min="0" step="0.1" placeholder="油费 / 公里" /><input v-model="revenueForm.accidentLossRate" type="number" min="0" max="1" step="0.01" placeholder="事故损失率 0-1" /><button @click="calculateRevenue">计算收益</button></div><pre v-if="revenue" class="result json">{{ JSON.stringify(revenue, null, 2) }}</pre></section>
    </aside>
  </div>
</template>

<style>
html, body, #app { margin: 0; min-width: 1180px; width: 100%; height: 100%; overflow: hidden; }
* { box-sizing: border-box; }
.app-shell { position: relative; width: 100%; height: 100%; font-family: Inter, "Microsoft YaHei", sans-serif; color: #172033; }
.control-panel { position: absolute; z-index: 10; top: 16px; right: 16px; bottom: 16px; width: 390px; overflow: auto; padding: 18px; border: 1px solid rgba(210,220,235,.95); border-radius: 18px; background: rgba(255,255,255,.95); box-shadow: 0 16px 50px rgba(27,48,84,.2); backdrop-filter: blur(12px); }
.panel-header { display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; margin-bottom: 16px; }.eyebrow { margin: 0 0 4px; color: #3b82f6; font-size: 10px; letter-spacing: .14em; font-weight: 800; }h1,h2,p { margin: 0; }h1 { font-size: 21px; letter-spacing: -.03em; }h2 { font-size: 14px; }.muted,.hint,.section-title span { color: #718096; font-size: 11px; }.muted { margin-top: 4px; }.icon-button { width: 34px; height: 34px; padding: 0; border-radius: 50%; font-size: 20px; }
.panel-section { padding: 14px 0; border-top: 1px solid #edf1f7; }.section-title { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 9px; }.button-row { display: flex; flex-wrap: wrap; gap: 7px; margin-top: 8px; }
button,input,select { min-height: 32px; border: 1px solid #d7dfeb; border-radius: 8px; background: #fff; color: #172033; font: inherit; font-size: 12px; }button { padding: 6px 10px; cursor: pointer; }button:hover { border-color: #82aaf7; }button:disabled { opacity: .5; cursor: not-allowed; }button.primary { border-color: #2563eb; background: #2563eb; color: #fff; }.form-action { margin-top: 7px; }
input,select { width: 100%; padding: 6px 8px; }.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 7px; }.hint { margin-top: 8px; line-height: 1.5; }.message { margin-bottom: 10px; padding: 8px 10px; border-radius: 8px; font-size: 12px; line-height: 1.45; }.message.error { background: #fff1f2; color: #be123c; }.message.success { background: #ecfdf5; color: #047857; }.result { margin-top: 9px; padding: 8px 10px; border-radius: 8px; background: #f5f8fc; color: #43536b; font-size: 11px; line-height: 1.6; }.result strong { color: #0f766e; }.result.json { max-height: 180px; overflow: auto; white-space: pre-wrap; }
@media (max-width: 1180px) { html,body,#app { min-width: 0; }.control-panel { left: 12px; right: 12px; width: auto; max-height: 52vh; } }
</style>
