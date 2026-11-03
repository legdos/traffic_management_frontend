/**
 * 仿真相关接口封装。所有路径都是相对路径，由 vite.config.js 的代理转发到后端。
 */

async function readJson(response) {
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }
  return response.json()
}

async function readText(response) {
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }
  return response.text()
}

/** 一次拿到轮次、车辆、三组任务 */
export function fetchState() {
  return fetch('/sim/state').then(readJson)
}

/** 某条路线的折线点 [[lng,lat],...] */
export function fetchRoutePoints(routeId) {
  return fetch(`/routes/${routeId}/points`).then(readJson)
}

export function startSim() {
  return fetch('/sim/start', { method: 'POST' }).then(readText)
}

export function stopSim() {
  return fetch('/sim/stop', { method: 'POST' }).then(readText)
}

/** 清空任务、车辆回到空闲 */
export function resetSim() {
  return fetch('/sim/reset', { method: 'POST' }).then(readText)
}
