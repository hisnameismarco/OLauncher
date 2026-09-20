// SPDX-License-Identifier: GPL-3.0-only
function isGrid(filter, query) {
  return filter === "app" && String(query || "").trim().length === 0
}

function payloadFilter(payload) {
  try {
    var value = typeof payload === "string" ? JSON.parse(payload) : payload
    return value && typeof value === "object" && !Array.isArray(value) && value.filter === "apps" ? "app" : "all"
  } catch (e) { return "all" }
}

function columnsForWidth(width) {
  return Math.max(1, Math.floor(width / 104))
}

function compareApps(a, b) {
  return a.title.localeCompare(b.title) || a.appId.localeCompare(b.appId)
}

function selectionId(apps, selectedId, previousIndex) {
  if (!apps.length) return ""
  if (apps.some(function(app) { return (app.key || app.appId) === selectedId })) return selectedId
  var item = apps[Math.max(0, Math.min(apps.length - 1, previousIndex))]
  return item.key || item.appId
}

function move(index, count, columns, direction) {
  if (count <= 0) return -1
  index = Math.max(0, Math.min(count - 1, index))
  columns = Math.max(1, columns)
  if (direction === "left") return Math.max(0, index - 1)
  if (direction === "right") return Math.min(count - 1, index + 1)
  if (direction === "up") return index < columns ? index : index - columns
  // Clamp to the last cell of an incomplete row; stay put on the final row.
  if (direction === "down") return Math.floor(index / columns) === Math.floor((count - 1) / columns) ? index : Math.min(count - 1, index + columns)
  if (direction === "pageUp") return Math.max(0, index - columns * 3)
  if (direction === "pageDown") return Math.min(count - 1, index + columns * 3)
  return index
}

if (typeof module !== "undefined") module.exports = {isGrid, payloadFilter, columnsForWidth, compareApps, selectionId, move}
