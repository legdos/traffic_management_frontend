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
    plugins: ['AMap.Scale', 'AMap.ToolBar']
  }).then((_AMap) => {
    AMap = _AMap;
    map = new AMap.Map('map-container', {
      viewMode: '2D',
      zoom: 12,
      center: [104.0668, 30.5728],
    });
    map.addControl(new AMap.Scale());
    map.addControl(new AMap.ToolBar());
    
    // 延迟 resize 确保地图容器渲染完毕
    setTimeout(() => map.resize(), 200);
    
    // 加载工厂
    loadFactories();
    // 加载车辆列表
    loadVehicles();
  }).catch(e => {
    console.error('高德地图加载失败:', e);
  });
});

function loadFactories() {
  fetch('/factories')
    .then(r => r.json())
    .then(data => {
      console.log('工厂数据:', data);
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
    .catch(err => console.error('加载工厂失败:', err));
}

function loadVehicles() {
  fetch('/vehicles')
    .then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const ct = r.headers.get('content-type');
      if (ct && !ct.includes('application/json')) {
        throw new Error('返回非JSON，请检查后端/代理');
      }
      return r.json();
    })
    .then(data => {
      console.log('车辆数据:', data);
      
      // 新增：用于收集有效车辆数据，供左侧列表使用
      const validVehicles = [];
      
      data.forEach(v => {
        console.log('车辆原始数据:', v);

        const lng = Number(v.currentLongitude);
        const lat = Number(v.currentLatitude);

        if (isNaN(lng) || isNaN(lat)) {
          console.warn('跳过无效坐标车辆:', v.id);
          return;
        }

        // 地图标记（保持原有代码不变）
        const marker = new AMap.Marker({
          position: [lng, lat],
          zIndex: 999,
          content: `<div style="background:#d9534f;color:white;padding:2px 8px;border-radius:12px;font-size:12px;box-shadow:0 2px 4px rgba(0,0,0,0.3);">🚗${v.id}</div>`,
          offset: new AMap.Pixel(-20, -10)
        });
        marker.setMap(map);

        // 新增：收集有效车辆数据
        validVehicles.push({
          id: v.id || v.bandName,
          currentAction: v.currentAction || 1,
          remainingTime: v.remainingTime || 0
        });
      });

      // 新增：更新左侧列表
      vehicles.value = validVehicles;

      if (data.length) map.setFitView();
    })
    .catch(err => console.error('加载车辆失败:', err));
}

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