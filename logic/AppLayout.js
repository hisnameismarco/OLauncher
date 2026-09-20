// SPDX-License-Identifier: GPL-3.0-only
var VERSION = 2

function uniqueIds(ids) {
  var seen = Object.create(null)
  return (Array.isArray(ids) ? ids : []).filter(function(id) {
    if (typeof id !== "string" || !id.length || seen[id]) return false
    seen[id] = true
    return true
  })
}

function parse(raw) {
  var result = {items:[], hidden:[], error:false, protected:false, migrated:false}
  if (raw === undefined || raw === null || String(raw).trim() === "") return result
  try {
    var data = JSON.parse(raw)
    if (data && typeof data.version === "number" && data.version > VERSION) {
      result.protected = true
      return result
    }
    if (data && data.version === 1 && Array.isArray(data.order)
        && data.order.every(function(id) { return typeof id === "string" && id.length > 0 })) {
      result.items = uniqueIds(data.order).map(appItem)
      result.migrated = true
    } else if (data && data.version === VERSION && Array.isArray(data.items)) {
      result.items = normalizeLayout(data.items)
      result.hidden = uniqueIds(data.hidden)
    } else result.error = true
  } catch (e) { result.error = true }
  return result
}

// defaultIds is the full catalog in display-name/ID order. Never mutates saved.
function reconcile(saved, defaultIds) {
  var available = uniqueIds(defaultIds), savedIds = uniqueIds(saved), set = Object.create(null), savedSet = Object.create(null)
  savedIds.forEach(function(id) { savedSet[id] = true })
  available.forEach(function(id) { set[id] = true })
  return savedIds.filter(function(id) { return set[id] === true })
    .concat(available.filter(function(id) { return !savedSet[id] }))
}

function moveId(order, id, targetIndex) {
  var next = uniqueIds(order), from = next.indexOf(id)
  if (from < 0 || !isFinite(targetIndex)) return next
  var to = Math.max(0, Math.min(next.length - 1, Math.floor(targetIndex)))
  next.splice(from, 1)
  next.splice(to, 0, id)
  return next
}

function insertionTarget(from, over, after, count) {
  var gap = Math.max(0, Math.min(count, over + (after ? 1 : 0)))
  return Math.max(0, Math.min(count - 1, gap > from ? gap - 1 : gap))
}

function maySave(loaded, protectedFile, dirty) { return loaded && !protectedFile && dirty }
function serialize(items, hidden) { return JSON.stringify({version:VERSION, items:normalizeLayout(items), hidden:uniqueIds(hidden)}) + "\n" }

function appItem(id) { return {type:"app", appId:id} }
function itemKey(item) { return item.type === "folder" ? "folder:" + item.id : "app:" + item.appId }
function folderName(value) { return String(value).trim().slice(0,64) || "Folder" }

// First occurrence wins globally. Always clone nested arrays. No nested folders.
function normalizeLayout(items) {
  var seen = Object.create(null), folders = Object.create(null), out = []
  function take(id) {
    if (typeof id !== "string" || !id.length || seen[id]) return false
    seen[id] = true
    return true
  }
  ;(Array.isArray(items) ? items : []).forEach(function(item) {
    if (!item || typeof item !== "object") return
    if (item.type === "app" && take(item.appId)) out.push(appItem(item.appId))
    else if (item.type === "folder" && typeof item.id === "string" && item.id.length
        && !folders[item.id] && typeof item.name === "string" && Array.isArray(item.apps)) {
      folders[item.id] = true
      var apps = item.apps.filter(take)
      if (apps.length === 1) out.push(appItem(apps[0]))
      else if (apps.length > 1) out.push({type:"folder",id:item.id,name:folderName(item.name),apps:apps})
    }
  })
  return out
}
function allAppIds(items) {
  return normalizeLayout(items).reduce(function(ids,item) {
    return ids.concat(item.type === "app" ? [item.appId] : item.apps)
  },[])
}
function reconcileLayout(saved, defaultIds) {
  var available = uniqueIds(defaultIds), present = Object.create(null)
  available.forEach(function(id) { present[id] = true })
  var visible = normalizeLayout(saved).map(function(item) {
    if (item.type === "app") return present[item.appId] ? item : null
    return {type:"folder",id:item.id,name:item.name,apps:item.apps.filter(function(id) { return present[id] })}
  }).filter(function(item) { return item !== null })
  visible = normalizeLayout(visible)
  var used = Object.create(null)
  allAppIds(visible).forEach(function(id) { used[id] = true })
  return visible.concat(available.filter(function(id) { return !used[id] }).map(appItem))
}
function moveRootItem(items, key, target) {
  var next = normalizeLayout(items), keys = next.map(itemKey)
  return moveId(keys,key,target).map(function(k) { return next[keys.indexOf(k)] })
}
function createFolder(items, sourceId, targetId, folderId) {
  var next = normalizeLayout(items)
  var source = next.find(function(i) { return i.type === "app" && i.appId === sourceId })
  var target = next.find(function(i) { return i.type === "app" && i.appId === targetId })
  if (!source || !target || sourceId === targetId || typeof folderId !== "string" || !folderId.length
      || next.some(function(i) { return i.type === "folder" && i.id === folderId })) return next
  // Replace target in-place, then remove source. Target app comes first inside.
  return next.filter(function(i) { return i !== source }).map(function(i) {
    return i === target ? {type:"folder",id:folderId,name:"Folder",apps:[targetId,sourceId]} : i
  })
}
function addAppToFolder(items, appId, folderId) {
  var next = normalizeLayout(items)
  if (!next.some(function(i) { return i.type === "app" && i.appId === appId })
      || !next.some(function(i) { return i.type === "folder" && i.id === folderId })) return next
  return next.filter(function(i) { return !(i.type === "app" && i.appId === appId) }).map(function(i) {
    return i.type === "folder" && i.id === folderId
      ? {type:"folder",id:i.id,name:i.name,apps:i.apps.concat([appId])} : i
  })
}
function removeAppFromFolder(items, folderId, appId) {
  var out = []
  normalizeLayout(items).forEach(function(item) {
    if (item.type === "folder" && item.id === folderId && item.apps.indexOf(appId) >= 0) {
      out.push({type:"folder",id:item.id,name:item.name,apps:item.apps.filter(function(id) { return id !== appId })})
      out.push(appItem(appId))
    } else out.push(item)
  })
  return normalizeLayout(out)
}
function moveAppInsideFolder(items, folderId, appId, target) {
  return normalizeLayout(items).map(function(i) {
    return i.type === "folder" && i.id === folderId
      ? {type:"folder",id:i.id,name:i.name,apps:moveId(i.apps,appId,target)} : i
  })
}
function renameFolder(items, folderId, name) {
  return normalizeLayout(items).map(function(i) {
    return i.type === "folder" && i.id === folderId && typeof name === "string" && name.trim().length
      ? {type:"folder",id:i.id,name:folderName(name),apps:i.apps.slice()} : i
  })
}
function deleteFolder(items, folderId) {
  return normalizeLayout(items).reduce(function(out,i) {
    return out.concat(i.type === "folder" && i.id === folderId ? i.apps.map(appItem) : [i])
  },[])
}
// Append discoveries without pruning stored membership (used when saving visibility).
function extendLayout(items, catalogIds) {
  var next = normalizeLayout(items), used = allAppIds(next)
  return next.concat(uniqueIds(catalogIds).filter(function(id) { return used.indexOf(id) < 0 }).map(appItem))
}

// Explicit structural edits may clean unavailable entries, but never hidden ones.
function reconcileWithHidden(items, catalogIds, hidden) {
  var stored = allAppIds(items)
  return reconcileLayout(items, uniqueIds(catalogIds).concat(uniqueIds(hidden).filter(function(id) { return stored.indexOf(id) >= 0 })))
}
function hiddenSet(hidden) {
  var set = Object.create(null)
  uniqueIds(hidden).forEach(function(id) { set[id] = true })
  return set
}
function changeHidden(hidden, operation, id) {
  var next = uniqueIds(hidden)
  if (operation === "hide") return uniqueIds(next.concat([id]))
  if (operation === "restore") return next.filter(function(value) { return value !== id })
  if (operation === "restoreAll") return []
  return next
}

// Visibility never normalizes/dissolves the filtered folder structure.
function filterVisibleLayout(items, hidden) {
  var excluded = hiddenSet(hidden)
  return items.reduce(function(out,item) {
    if (item.type === "app") { if (!excluded[item.appId]) out.push(appItem(item.appId)) }
    else {
      var apps = item.apps.filter(function(id) { return !excluded[id] })
      if (apps.length) out.push({type:"folder",id:item.id,name:item.name,apps:apps})
    }
    return out
  },[])
}
function filterAppResults(rows, hidden) {
  var excluded = hiddenSet(hidden)
  return rows.filter(function(row) { return row.kind !== "app" || !excluded[row.appId] })
}

// Move only the dragged record, before/after the stable visible target anchor.
// Every other record, including hidden records, retains its relative order.
function anchoredMove(fullIds, visibleIds, id, target) {
  var full = uniqueIds(fullIds), visible = uniqueIds(visibleIds).filter(function(key) { return full.indexOf(key) >= 0 })
  var from = visible.indexOf(id)
  if (from < 0 || !isFinite(target)) return full
  var to = Math.max(0, Math.min(visible.length - 1, Math.floor(target)))
  if (from === to) return full
  var anchor = visible[to]
  var without = full.filter(function(key) { return key !== id })
  without.splice(without.indexOf(anchor) + (to > from ? 1 : 0),0,id)
  return without
}
function moveVisibleRoot(items, key, target, visibleKeys) {
  var next = normalizeLayout(items), keys = next.map(itemKey)
  return anchoredMove(keys,visibleKeys,key,target).map(function(k) { return next[keys.indexOf(k)] })
}
function moveVisibleInside(items, folderId, appId, target, visibleIds) {
  return normalizeLayout(items).map(function(item) {
    return item.type === "folder" && item.id === folderId
      ? {type:"folder",id:item.id,name:item.name,apps:anchoredMove(item.apps,visibleIds,appId,target)} : item
  })
}
function operate(items, operation, args) {
  if (operation === "moveVisible") return moveVisibleRoot(items,args[0],args[1],args[2])
  if (operation === "insideVisible") return moveVisibleInside(items,args[0],args[1],args[2],args[3])
  if (operation === "move") return moveRootItem(items,args[0],args[1])
  if (operation === "create") return createFolder(items,args[0],args[1],args[2])
  if (operation === "add") return addAppToFolder(items,args[0],args[1])
  if (operation === "remove") return removeAppFromFolder(items,args[0],args[1])
  if (operation === "inside") return moveAppInsideFolder(items,args[0],args[1],args[2])
  if (operation === "rename") return renameFolder(items,args[0],args[1])
  if (operation === "delete") return deleteFolder(items,args[0])
  return normalizeLayout(items)
}

if (typeof module !== "undefined") module.exports = {VERSION, uniqueIds, parse, reconcile, moveId, insertionTarget, maySave, serialize,
  appItem,itemKey,folderName,normalizeLayout,allAppIds,reconcileLayout,moveRootItem,createFolder,addAppToFolder,
  removeAppFromFolder,moveAppInsideFolder,renameFolder,deleteFolder,operate,extendLayout,reconcileWithHidden,hiddenSet,changeHidden,filterVisibleLayout,filterAppResults,anchoredMove,moveVisibleRoot,moveVisibleInside}
