<template>
  <div>
    <!-- 马表控制与信息 -->
    <div class="sim-panel">
      <span>马表循环: 第 {{ tickCount }} 次</span>
      <button @click="startSim">启动仿真</button>
      <button @click="stopSim">停止</button>
    </div>

    <!-- 左侧车辆列表 -->
    <div class="vehicle-list">
      <h3>车辆状态</h3>
      <div v-for="v in vehicles" :key="v.id" class="vehicle-item">
        <span>车辆{{ v.id }}</span>
        <span :class="'status-' + v.currentAction">{{ statusMap[v.currentAction] || '未知' }}</span>
        <span>剩余: {{ v.remainingTime }}分钟</span>
      </div>
    </div>

    <div id="map-container" style="width: 100%; height: 100vh;"></div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import AMapLoader from '@amap/amap-jsapi-loader';

let map = null;
let AMap = null;
const tickCount = ref(0);
const vehicles = ref([]);
let simTimer = null;

const statusMap = {
  1: '空闲', 2: '接单行驶', 3: '装货',
  4: '运货行驶', 5: '卸货', 6: '等待', 7: '初始化'
};

onMounted(() => {
  window._AMapSecurityConfig = {
    securityJsCode: 'bb2549ae73d47cd79a1a27535a9e8f25',
  };
  
  AMapLoader.load({
    key: '4fe176fc16d356769714d97913538dce',
    version: '2.0',
    plugins: ['AMap.Scale', 'AMap.ToolBar', 'AMap.PlaceSearch']
  }).then((_AMap) => {
    AMap = _AMap;
    // ----- 1. 创建地图（底图载入）-----
    map = new AMap.Map('map-container', {
      viewMode: '2D',
      zoom: 12,
      center: [104.0668, 30.5728],
    });
    map.addControl(new AMap.Scale());
    map.addControl(new AMap.ToolBar());
    setTimeout(() => map.resize(), 100);
    setTimeout(() => map.resize(), 500);

    // ----- 2. POI搜索真实工厂并自动入库（无按钮）-----
    const placeSearch = new AMap.PlaceSearch({
      type: '工厂',
      city: '成都',
      pageSize:0,
      pageIndex: 1
    });

    placeSearch.search('工厂', (status, result) => {
      if (status === 'complete' && result.poiList) {
        const pois = result.poiList.pois;
        console.log(`搜索到 ${pois.length} 个工厂，开始自动入库...`);
        
        pois.forEach((poi, index) => {
          const factoryData = {
            factoryName: poi.name,
            address: poi.address || '',
            phone: '',
            factoryLongitude: poi.location.lng,
            factoryLatitude: poi.location.lat,
            needId: 1
          };

          // 注意：这是相对路径 /api/...，而非 localhost:8080
          fetch('/factories', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(factoryData)
          })
          .then(res => res.text())
          .then(msg => console.log(`第${index+1}个入库成功:`, poi.name))
          .catch(err => console.error(`第${index+1}个入库失败:`, err));
        });
      } else {
        console.warn('POI搜索无结果或失败', status);
      }
    });

    // ----- 3. 加载已入库工厂到地图显示-----
    loadFactories();
  }).catch(e => {
    console.error('高德地图加载失败', e);
  });
});

// ----- 加载已入库工厂并在地图上打点 -----
function loadFactories() {
  fetch('/factories')
    .then(r => r.json())
    .then(data => {
      data.forEach(f => {
        const marker = new AMap.Marker({
          position: [f.factoryLongitude, f.factoryLatitude],
          title: f.factoryName,
          label: { content: f.factoryName, direction: 'top' }
        });
        marker.setMap(map);
      });
      if (data.length) map.setFitView();
    })
    .catch(err => console.error('加载工厂失败', err));
}

// ----- 新增：加载车辆列表 -----
function loadVehicles() {
  fetch('/vehicles')
    .then(r => r.json())
    .then(data => { vehicles.value = data; })
    .catch(err => console.error('加载车辆失败', err));
}

// ----- 新增：马表控制 -----
function startSim() {
  fetch('/sim/start', { method: 'POST' });
  loadVehicles();
  if (simTimer) clearInterval(simTimer);
  simTimer = setInterval(() => {
    tickCount.value++;
    loadVehicles();
  }, 3000);
}

function stopSim() {
  fetch('/sim/stop', { method: 'POST' });
  if (simTimer) {
    clearInterval(simTimer);
    simTimer = null;
  }
}

onUnmounted(() => {
  stopSim();
  if (map) map.destroy();
});
</script>

<style scoped>
#map-container {
  width: 100vw;
  height: 100vh;
  position: fixed;
  top: 0;
  left: 0;
  background: #eee;
  z-index: 1;
}
.sim-panel {
  position: absolute;
  top: 20px;
  left: 220px;
  z-index: 10;
  background: rgba(255,255,255,0.9);
  padding: 10px 15px;
  border-radius: 6px;
}
.vehicle-list {
  position: absolute;
  top: 70px;
  left: 20px;
  z-index: 10;
  background: rgba(255,255,255,0.95);
  padding: 10px;
  border-radius: 6px;
  min-width: 180px;
  max-height: 75vh;
  overflow-y: auto;
}
.vehicle-item {
  display: flex;
  gap: 8px;
  padding: 4px 0;
  border-bottom: 1px solid #eee;
  font-size: 13px;
}
.status-1 { color: green; }
.status-2 { color: blue; }
.status-3 { color: orange; }
.status-4 { color: purple; }
.status-5 { color: red; }
.status-6 { color: gray; }
.status-7 { color: black; }
</style>