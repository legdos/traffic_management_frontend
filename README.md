# 运输车辆调度控制台

这是基于原 `traffic_management_frontend-main` 的前端升级副本，面向 `traffic backend` 的接口。

## 运行

1. 复制 `.env.example` 为 `.env.local`，填写高德 JS API Key 和安全密钥。
2. 确认后端运行在 `http://127.0.0.1:8080`，或调整 `vite.config.js` 中的代理地址。
3. 执行 `npm install` 和 `npm run dev`。

## 已加入的交互

- 手动刷新工厂、需求、车辆和 POI。
- 点击后才执行高德工厂搜索与写库，导入过程在前端做本次结果去重。
- 新增工厂、需求、车辆和 POI；对工厂、需求、车辆和 POI 执行带确认的失效操作。
- 计算需求与车辆匹配度、创建运输任务、计算收益。
- 更新车辆状态、单步推进和启动/暂停位置仿真。

`src/api.js` 集中封装后端请求；`src/components/MapView.vue` 只负责地图与标记渲染。仿真按钮依赖后端完成数据库扩展迁移后才能使用车辆 `version` 乐观锁字段。
