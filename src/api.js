const API_BASE = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '')

async function request(path, options = {}) {
  const { headers: suppliedHeaders, ...requestOptions } = options
  const response = await fetch(`${API_BASE}${path}`, {
    ...requestOptions,
    headers: {
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(suppliedHeaders || {}),
    },
  })

  const text = await response.text()
  let body = null
  if (text) {
    try {
      body = JSON.parse(text)
    } catch {
      body = text
    }
  }
  if (!response.ok) {
    const message = typeof body === 'string' ? body : body?.message || body?.error || `请求失败（${response.status}）`
    throw new Error(message)
  }
  return body
}

const json = (method, body) => ({ method, body: JSON.stringify(body) })

export const api = {
  listFactories: () => request('/factories'),
  createFactory: (payload) => request('/factories', json('POST', payload)),
  updateFactory: (payload) => request('/factories', json('PUT', payload)),
  generateNeedFromFactory: (id, material) => request(`/factories/${id}/generate-need?material=${encodeURIComponent(material)}`, { method: 'POST' }),
  deactivateFactory: (id) => request(`/factories/${id}`, { method: 'DELETE' }),

  listNeeds: () => request('/needs'),
  createNeed: (payload) => request('/needs', json('POST', payload)),
  deactivateNeed: (id) => request(`/needs/${id}`, { method: 'DELETE' }),

  listVehicles: () => request('/vehicles/active'),
  createVehicle: (payload) => request('/vehicles', json('POST', payload)),
  deactivateVehicle: (id) => request(`/vehicles/${id}/deactivate`, { method: 'DELETE' }),
  updateVehiclePosition: (id, payload) => request(`/vehicles/${id}/position`, json('PUT', payload)),
  updateVehicleState: (id, payload) => request(`/vehicles/${id}/state`, json('PUT', payload)),

  listPois: () => request('/pois'),
  createPoi: (payload) => request('/pois', json('POST', payload)),
  deactivatePoi: (id) => request(`/pois/${id}`, { method: 'DELETE' }),

  listActions: () => request('/actions'),
  createAction: (payload) => request('/actions', json('POST', payload)),
  updateAction: (payload) => request('/actions', json('PUT', payload)),
  deleteAction: (id) => request(`/actions/${id}`, { method: 'DELETE' }),

  scoreMatching: (needId, vehicleId) => request(`/matching/score?needId=${encodeURIComponent(needId)}&vehicleId=${encodeURIComponent(vehicleId)}`),
  createTask: (payload) => request('/tasks', json('POST', payload)),
  getRevenue: (taskId, params = {}) => {
    const query = new URLSearchParams()
    Object.entries(params).forEach(([key, value]) => {
      if (value !== '' && value !== null && value !== undefined) query.set(key, value)
    })
    const suffix = query.toString() ? `?${query}` : ''
    return request(`/tasks/${taskId}/revenue${suffix}`)
  },

  simulationStatus: () => request('/simulation/status'),
  startSimulation: () => request('/simulation/start', { method: 'POST' }),
  pauseSimulation: () => request('/simulation/pause', { method: 'POST' }),
  stepSimulation: () => request('/simulation/step', { method: 'POST' }),
}

export { API_BASE }
