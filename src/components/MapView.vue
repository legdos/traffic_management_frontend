<script setup>
import { nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import AMapLoader from '@amap/amap-jsapi-loader'

const props = defineProps({
  factories: { type: Array, default: () => [] },
  pois: { type: Array, default: () => [] },
  vehicles: { type: Array, default: () => [] },
})

const mapContainer = ref(null)
const mapError = ref('')
let map = null
let AMap = null
let placeSearch = null
let factoryMarkers = []
let poiMarkers = []
let vehicleMarkers = []

function coords(item, latKey, lngKey) {
  const lat = Number(item?.[latKey])
  const lng = Number(item?.[lngKey])
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? [lng, lat] : null
}

function clearMarkers(markers) { markers.forEach((marker) => marker.setMap(null)); markers.splice(0) }

function markerContent(text, className) {
  const node = document.createElement('div')
  node.className = `map-marker ${className}`
  node.textContent = text
  return node
}

function renderMarkers() {
  if (!map || !AMap) return
  clearMarkers(factoryMarkers); clearMarkers(poiMarkers); clearMarkers(vehicleMarkers)
  props.factories.forEach((factory) => {
    const position = coords(factory, 'factoryLatitude', 'factoryLongitude')
    if (!position) return
    const marker = new AMap.Marker({ position, content: markerContent('厂', 'factory-marker'), title: factory.factoryName || `工厂 ${factory.id}` })
    marker.setMap(map); factoryMarkers.push(marker)
  })
  props.pois.forEach((poi) => {
    const position = coords(poi, 'poiLatitude', 'poiLongitude')
    if (!position) return
    const marker = new AMap.Marker({ position, content: markerContent('点', 'poi-marker'), title: poi.poiName || `POI ${poi.id}` })
    marker.setMap(map); poiMarkers.push(marker)
  })
  props.vehicles.forEach((vehicle) => {
    const position = coords(vehicle, 'currentLatitude', 'currentLongitude')
    if (!position) return
    const marker = new AMap.Marker({ position, content: markerContent('车', `vehicle-marker ${String(vehicle.status || '').toLowerCase()}`), title: vehicle.licenseNumber || vehicle.bandName || `车辆 ${vehicle.id}` })
    marker.setMap(map); vehicleMarkers.push(marker)
  })
}

function searchFactories() {
  return new Promise((resolve, reject) => {
    if (!placeSearch) return reject(new Error('地图搜索插件尚未加载'))
    placeSearch.search('工厂', (status, result) => {
      if (status === 'complete' && result?.poiList?.pois) resolve(result.poiList.pois)
      else reject(new Error(`高德 POI 搜索失败：${status || 'unknown'}`))
    })
  })
}

defineExpose({ searchFactories })

onMounted(async () => {
  const key = import.meta.env.VITE_AMAP_KEY
  const securityJsCode = import.meta.env.VITE_AMAP_SECURITY_CODE
  if (!key || !securityJsCode) {
    mapError.value = '未配置 VITE_AMAP_KEY / VITE_AMAP_SECURITY_CODE，地图不会加载。请复制 .env.example 并填写高德配置。'
    return
  }
  window._AMapSecurityConfig = { securityJsCode }
  try {
    AMap = await AMapLoader.load({ key, version: '2.0', plugins: ['AMap.Scale', 'AMap.ToolBar', 'AMap.PlaceSearch'] })
    map = new AMap.Map(mapContainer.value, { viewMode: '2D', zoom: 11, center: [104.0668, 30.5728] })
    map.addControl(new AMap.Scale()); map.addControl(new AMap.ToolBar())
    placeSearch = new AMap.PlaceSearch({ type: '工厂', city: import.meta.env.VITE_AMAP_CITY || '成都', pageSize: 100, pageIndex: 1 })
    await nextTick(); renderMarkers(); map.resize()
  } catch (reason) { mapError.value = reason instanceof Error ? reason.message : String(reason) }
})

watch(() => [props.factories, props.pois, props.vehicles], renderMarkers, { deep: true })
onUnmounted(() => { clearMarkers(factoryMarkers); clearMarkers(poiMarkers); clearMarkers(vehicleMarkers); if (map) map.destroy() })
</script>

<template>
  <div ref="mapContainer" class="map-container">
    <div v-if="mapError" class="map-error">{{ mapError }}</div>
    <div class="map-legend"><span><i class="factory-dot">厂</i>工厂</span><span><i class="poi-dot">点</i>POI</span><span><i class="vehicle-dot">车</i>车辆</span></div>
  </div>
</template>

<style>
.map-container { position: absolute; inset: 0; background: #eaf0f7; }
.map-error { position: absolute; z-index: 2; top: 18px; left: 18px; max-width: 520px; padding: 10px 12px; border-radius: 10px; background: rgba(255, 247, 237, .94); color: #9a3412; font: 12px/1.5 Inter, "Microsoft YaHei", sans-serif; box-shadow: 0 6px 20px rgba(45, 55, 72, .12); }
.map-legend { position: absolute; z-index: 2; bottom: 18px; left: 18px; display: flex; gap: 10px; padding: 8px 10px; border-radius: 10px; background: rgba(255, 255, 255, .9); color: #4a5568; font: 11px Inter, "Microsoft YaHei", sans-serif; box-shadow: 0 6px 20px rgba(45, 55, 72, .12); }.map-legend span { display: flex; align-items: center; gap: 4px; }.map-legend i { display: inline-flex; align-items: center; justify-content: center; width: 18px; height: 18px; border-radius: 50%; color: #fff; font-style: normal; font-size: 10px; font-weight: 700; }.factory-dot { background: #2563eb; }.poi-dot { background: #8b5cf6; }.vehicle-dot { background: #059669; }
.map-marker { display: flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: 2px solid #fff; border-radius: 50%; color: #fff; font: 11px "Microsoft YaHei", sans-serif; box-shadow: 0 2px 8px rgba(15, 23, 42, .35); }.factory-marker { background: #2563eb; }.poi-marker { background: #8b5cf6; }.vehicle-marker { background: #059669; }.vehicle-marker.assigned,.vehicle-marker.loading,.vehicle-marker.transporting,.vehicle-marker.unloading { background: #f59e0b; }.vehicle-marker.maintenance { background: #dc2626; }
</style>
