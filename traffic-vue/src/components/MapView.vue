<template>
  <div id="map-container" style="width: 100%; height: 100vh;"></div>
</template>

<script setup>
import { onMounted, onUnmounted } from 'vue';
import AMapLoader from '@amap/amap-jsapi-loader';

let map = null;

onMounted(() => {
  window._AMapSecurityConfig = {
    securityJsCode: 'bb2549ae73d47cd79a1a27535a9e8f25',
  };
  
  AMapLoader.load({
    key: '4fe176fc16d356769714d97913538dce',
    version: '2.0',
    plugins: ['AMap.Scale', 'AMap.ToolBar', 'AMap.PlaceSearch']
  }).then((AMap) => {
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
      pageSize: 100,
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
  }).catch(e => {
    console.error('高德地图加载失败', e);
  });
});

onUnmounted(() => {
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
</style>