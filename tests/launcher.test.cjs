// SPDX-License-Identifier: GPL-3.0-only
// Exercise the shipped QML's JavaScript, with process/UI effects replaced by fakes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const GridNavigation = require('../logic/GridNavigation.js');
const AppLayout = require('../logic/AppLayout.js');
require('./app-layout.test.cjs');
require('./folders.test.cjs');
require('./hidden.test.cjs');
require('./grid-navigation.test.cjs');
const qml = fs.readFileSync(path.join(__dirname, '..', 'Spotlight.qml'), 'utf8');
const source = qml.slice(qml.indexOf('  function open('), qml.indexOf('  AppLayoutStore {'));
function fixture() {
  const launched = [], saved = [];
  const root = {opened: true, query: '', filter: 'all', usage: {}, usageLoaded: true,
    persistentLayout: [], gridStructure: [], hiddenOpen:false, gridLayout: [], openFolderId:'', folderSelectedId:'', folderSerial:0, gridCatalog: [], gridApps: [], gridSelectedId: '', filters: [{key:'all'}, {key:'app'}, {key:'file'}, {key:'calc'}],
    quickApps: [], quickOpen: false, quickIndex: 0, actionsOpen: false, actionIndex: 0,
    immediate: [], files: [], results: [], selected: 0, generation: 0, appLibrary: null};
  Object.defineProperties(root, {
    expanded: {get: () => root.query.trim().length > 0 || root.filter !== 'all'},
    commandMode: {get: () => root.query.trim().startsWith('>')},
    gridActive: {get: () => GridNavigation.isGrid(root.filter, root.query)},
    gridSelectedIndex: {get: () => root.gridApps.findIndex(a => a.key === root.gridSelectedId)},
    openFolder: {get: () => root.gridApps.find(a => a.folderId === root.openFolderId && a.kind === 'folder') || null},
    folderApps: {get: () => root.openFolder ? root.openFolder.children : []},
    folderSelectedIndex: {get: () => root.folderApps.findIndex(a => a.key === root.folderSelectedId)},
    activeGridApps: {get: () => root.openFolder ? root.folderApps : root.gridApps},
    activeGridIndex: {get: () => root.openFolder ? root.folderSelectedIndex : root.gridSelectedIndex},
    current: {get: () => root.hiddenOpen ? null : root.gridActive ? root.activeGridApps[root.activeGridIndex] || null : root.results[root.selected] || null},
    actions: {get: () => [{key:'open'}, {key:'copy'}]}
  });
  const Qt = {iconPath: x => x || 'fallback', ShiftModifier: 1, ControlModifier: 2, callLater: fn => fn()};
  ['Escape','Tab','Backtab','Return','Enter','Left','Right','Down','Up','PageDown','PageUp','H']
    .forEach((name, i) => Qt['Key_' + name] = i + 10);
  const layoutStore = {items:[],hidden:[], setVisibility(operation,id,items) {
    const next=AppLayout.changeHidden(this.hidden,operation,id);
    if (JSON.stringify(next)===JSON.stringify(this.hidden)) return false;
    if (operation==='hide') this.items=AppLayout.normalizeLayout(items); this.hidden=next; root.visibilityChanged(); return true;
  }, get order() {return AppLayout.allAppIds(this.items)}, mutate(items, operation, args) {
    this.items = AppLayout.operate(items,operation,args); root.applyGridLayout(); return true;
  }};
  const ctx = vm.createContext({root, Qt, Quickshell: Qt, GridNavigation, AppLayout, layoutStore, hiddenView:{moveSelection(){},activateSelected(){}}, folderView:{columns:4,dragging:false,cancelDrag(){},cancelRename(){},beginRename(){}}, appGrid: {columns:4, dragging:false, cancelDrag(){}},
    DesktopEntries: {applications: {values: []}},
    usageFile: {setText: data => saved.push(JSON.parse(data))},
    input: {forceActiveFocus() {}}, debounce: {stop(){}, restart(){}}, fileProc: {running:false},
    Util: {shellQuote: x => JSON.stringify(x), execDetached: cmd => launched.push(cmd)}});
  vm.runInContext(source, ctx);
  for (const m of source.matchAll(/^  function (\w+)\(/gm)) root[m[1]] = ctx[m[1]];
  return {root, ctx, launched, saved, Qt};
}
{
  const {root, ctx} = fixture();
  ctx.DesktopEntries.applications.values = Array.from({length: 20}, (_,i) => ({id:'app'+i,name:'App '+String(i).padStart(2,'0'),icon:'app'}));
  root.usage = {app19: 500, app18: 50, app17: 49, app16: 48};
  assert.equal(root.frequentApps().map(a=>a.appId).join(','), 'app19,app18,app17,app16', 'rank entire catalog by raw counts, not capped search scores');
  ctx.DesktopEntries.applications.values[19].noDisplay = true;
  assert.equal(root.frequentApps()[0].appId, 'app18', 'exclude hidden entries');
  root.usage = {};
  assert.equal(root.frequentApps()[0].appId, 'app0', 'deterministic onboarding');
  ctx.DesktopEntries.applications.values = [];
  assert.equal(root.frequentApps().length, 0);
}
{
  const {root, ctx, launched, saved, Qt} = fixture();
  root.quickApps = [{appId:'demo',title:'Demo',kind:'app'}];
  root.handleKey({key:Qt.Key_Tab,modifiers:0});
  assert.equal(root.quickOpen,true);
  assert.equal(root.actionsOpen,false);
  root.handleEscape(); assert.equal(root.quickOpen,false);
  root.cycleQuick(1);
  root.activateSelected();
  assert.equal(launched.length,1);
  assert.equal(saved[0].demo,1);
  assert.equal(root.opened,false);
  root.opened=true; root.query='demo'; root.results=[root.quickApps[0]];
  root.performAction('open');
  assert.equal(saved[1].demo,2,'both launch paths share persisted counts');
  root.opened=true; root.query='demo'; root.quickOpen=false;
  root.handleKey({key:Qt.Key_Tab,modifiers:0});
  assert.equal(root.actionsOpen,true,'Tab with results opens actions');
  assert.equal(root.quickOpen,false);
}
{
  const {root} = fixture();
  assert.equal(root.calculate('125*1,19'),'148,75');
  assert.equal(root.calculate('200*15%'),'30');
  assert.equal(root.calculate('1/0'),null);
  root.quickOpen=true; root.query='hello'; root.refresh();
  assert.equal(root.quickOpen,false,'typing retracts circles');
  assert.equal(root.immediate.some(r=>r.kind==='cmd'),false);
  root.query='> echo hello'; root.refresh();
  assert.equal(root.immediate[0].kind,'cmd');
  root.generation=7; root.files=[];
  root.acceptFiles(JSON.stringify({token:6,paths:['/old']}));
  assert.equal(root.files.length,0,'stale results rejected');
}
console.log('PASS: most-used ranking, onboarding, hidden apps, empty catalogs, Tab routing, launch counts, persistence, calculations, command prefix and stale results.');

{
  const {root, ctx, saved, launched, Qt} = fixture();
  const entries = Array.from({length:300}, (_, i) => ({id:'id.'+i, name:'App '+String(i).padStart(3,'0'), icon:'app'}));
  const queries = [], appLaunches = [];
  root.appLibrary = {
    sortedEntries(q) { queries.push(q); return entries.map(entry => ({entry})); },
    entryName(e) { return e.name; }, entrySubtext() { return ''; }, iconSource(i) { return i; },
    launch(id) { appLaunches.push(id); }
  };
  root.refreshGridCatalog();
  assert.equal(root.gridApps.length,300);
  assert.equal(queries.join(','),'','grid requests only full catalog');
  assert.equal(root.gridSelectedId,'app:id.0');
  root.usage = {'id.299':999};
  const searchBefore = JSON.stringify(root.appResults('App'));
  const frequentBefore = JSON.stringify(root.frequentApps());
  root.refreshGridCatalog();
  assert.equal(root.gridApps[0].appId,'id.0','usage does not order grid');
  assert.equal(JSON.stringify(root.appResults('App')),searchBefore);
  assert.equal(JSON.stringify(root.frequentApps()),frequentBefore);
  root.open('{"filter":"apps"}');
  assert.equal(root.gridActive,true);
  root.handleKey({key:Qt.Key_Down, modifiers:0});
  assert.equal(root.gridSelectedId,'app:id.4');
  root.handleKey({key:Qt.Key_Right, modifiers:0});
  assert.equal(root.gridSelectedId,'app:id.5');
  root.handleKey({key:Qt.Key_Up, modifiers:0});
  root.handleKey({key:Qt.Key_Left, modifiers:0});
  assert.equal(root.gridSelectedId,'app:id.0');
  root.gridSelectedId='app:id.50';
  root.query='App'; root.refresh();
  assert.equal(root.gridActive,false);
  root.query=''; root.refresh();
  assert.equal(root.gridSelectedId,'app:id.50');
  entries.unshift({id:'new',name:'AAA',icon:'app'});
  root.refreshGridCatalog();
  assert.equal(root.gridSelectedId,'app:id.50','insertion preserves identity');
  entries.splice(entries.findIndex(e => e.id === 'id.50'),1);
  root.refreshGridCatalog();
  assert.equal(root.gridSelectedId,'app:id.51','removal chooses nearest index');
  root.handleKey({key:Qt.Key_Tab,modifiers:0});
  assert.equal(root.actionsOpen,true);
  assert.equal(root.quickOpen,false);
  root.handleEscape(); assert.equal(root.actionsOpen,false);
  root.handleKey({key:Qt.Key_Return,modifiers:0});
  assert.equal(appLaunches[0],'id.51');
  assert.equal(saved[0]['id.51'],1);
  assert.equal(root.opened,false);
  root.open('{"filter":"apps"}');
  root.activateGrid('id.52');
  assert.equal(appLaunches[1],'id.52','click uses shared launch path');
  assert.equal(saved[1]['id.52'],1);
  root.open('{"filter":"apps"}');
  root.handleKey({key:Qt.Key_Left,modifiers:Qt.ControlModifier});
  assert.equal(root.filter,'all');
  root.handleKey({key:Qt.Key_Right,modifiers:Qt.ControlModifier});
  assert.equal(root.filter,'app');
  root.handleEscape(); assert.equal(root.filter,'all');
  root.open('invalid'); assert.equal(root.filter,'all');
  root.open('{"filter":"apps"}');
  entries.length=0; root.refreshGridCatalog();
  assert.equal(root.gridSelectedIndex,-1);
  root.handleKey({key:Qt.Key_Return,modifiers:0});
  assert.equal(appLaunches.length,2,'empty grid cannot launch stale result');
}
console.log('PASS: grid integration (300 apps), stable selection, catalog changes, independent rankings, typing transitions, Tab/actions, launch counts, payload and Escape/filter routing.');

{
  const {root, ctx} = fixture();
  ctx.DesktopEntries.applications.values = [0,1,2,3].map(i => ({id:'a'+i,name:'App '+i,icon:'app'}));
  root.refreshGridCatalog(); root.filter='app';
  const search = JSON.stringify(root.appResults(''));
  const frequent = JSON.stringify(root.frequentApps());
  root.reorderGrid('a0',3);
  assert.equal(root.gridApps.map(a => a.appId).join(','),'a1,a2,a3,a0');
  assert.equal(root.gridSelectedId,'app:a0');
  assert.equal(root.gridSelectedIndex,3);
  assert.equal(JSON.stringify(root.appResults('')),search);
  assert.equal(JSON.stringify(root.frequentApps()),frequent);
  root.query='App'; root.refresh(); root.query=''; root.refresh();
  assert.equal(root.gridApps.map(a => a.appId).join(','),'a1,a2,a3,a0');
  ctx.DesktopEntries.applications.values.push({id:'new',name:'AAA',icon:'app'});
  root.refreshGridCatalog();
  assert.equal(root.gridApps.map(a => a.appId).join(','),'a1,a2,a3,a0,new');
  ctx.DesktopEntries.applications.values.splice(0,1); root.refreshGridCatalog();
  assert.equal(root.gridApps.map(a => a.appId).join(','),'a1,a2,a3,new');
  assert.equal(root.gridSelectedId,'app:new');
  assert.equal(ctx.layoutStore.order.join(','),'a1,a2,a3,a0','catalog cleanup is projection-only');
  ctx.DesktopEntries.applications.values=[]; root.refreshGridCatalog();
  assert.equal(root.gridApps.length,0);
  assert.equal(ctx.layoutStore.order.join(','),'a1,a2,a3,a0');
}
console.log('PASS: manual order isolated from search/usage, search transitions, selection, and catalog updates.');

{
  const {root,ctx,saved,Qt} = fixture();
  ctx.DesktopEntries.applications.values = ['A','B','C','D'].map(id => ({id,name:id,icon:'app'}));
  root.refreshGridCatalog(); root.filter='app';
  const search=JSON.stringify(root.appResults(''));
  const circles=JSON.stringify(root.frequentApps());
  root.folderDrop('app:A','app:B');
  const folderId=root.gridApps[0].folderId;
  assert.ok(folderId.startsWith('folder-'));
  assert.equal(root.gridSelectedId,'folder:'+folderId);
  assert.equal(JSON.stringify(root.appResults('')),search);
  assert.equal(JSON.stringify(root.frequentApps()),circles);
  root.handleKey({key:Qt.Key_Enter,modifiers:0});
  assert.equal(root.openFolderId,folderId);
  assert.equal(root.folderSelectedId,'app:B');
  root.moveGridSelection('right'); assert.equal(root.folderSelectedId,'app:A');
  root.reorderGrid('app:A',0); assert.equal(root.folderApps[0].appId,'A');
  root.renameGridFolder(' Development '); assert.equal(root.openFolder.title,'Development');
  assert.equal(root.openFolderId,folderId);
  root.handleEscape(); assert.equal(root.openFolderId,'');
  assert.equal(root.gridSelectedId,'folder:'+folderId);
  root.folderDrop('app:C','folder:'+folderId);
  root.openGridFolder(folderId);
  assert.equal(root.folderApps.length,3);
  root.performAction('removeFromFolder');
  assert.equal(root.folderApps.length,2);
  assert.equal(root.gridApps[1].appId,'A');
  root.handleEscape(); root.performAction('deleteFolder');
  assert.equal(root.gridApps.map(a=>a.appId).join(','),'B,C,A,D');
  assert.ok(root.gridSelectedIndex>=0);
  root.folderDrop('app:B','app:C');
  root.openGridFolder(root.gridApps[0].folderId);
  root.performAction('removeFromFolder');
  assert.equal(root.openFolderId,'','two-app removal dissolves folder');
  assert.ok(root.gridSelectedIndex>=0);
  root.folderDrop('app:B','app:C');
  root.openGridFolder(root.gridApps[0].folderId);
  root.handleKey({key:Qt.Key_Enter,modifiers:0});
  assert.equal(saved[0].C,1,'folder launch uses existing usage path');
  assert.equal(root.opened,false);
}
console.log('PASS: folder root/child selection, keyboard open/launch, Escape, rename, removal/dissolve, delete and flat ranking regression.');

{
  const {root,ctx} = fixture();
  ctx.DesktopEntries.applications.values=['A','B','C','D'].map(id=>({id,name:id,icon:'app'}));
  root.refreshGridCatalog(); root.filter='app';
  root.folderDrop('app:A','app:B');
  const id=root.gridApps[0].folderId;
  root.folderDrop('app:C','folder:'+id); root.openGridFolder(id);
  root.folderSelectedId='app:A';
  const persisted=JSON.stringify(ctx.layoutStore.items);
  ctx.DesktopEntries.applications.values=ctx.DesktopEntries.applications.values.filter(e=>e.id!=='A');
  root.refreshGridCatalog();
  assert.equal(root.folderSelectedId,'app:C');
  assert.equal(root.folderApps.length,2);
  assert.equal(JSON.stringify(ctx.layoutStore.items),persisted);
  ctx.DesktopEntries.applications.values=[]; root.refreshGridCatalog();
  assert.equal(root.openFolderId,'');
  assert.equal(root.gridSelectedIndex,-1);
  assert.equal(JSON.stringify(ctx.layoutStore.items),persisted);
  ctx.DesktopEntries.applications.values=['A','B','C','D','new'].map(id=>({id,name:id,icon:'app'}));
  root.refreshGridCatalog();
  assert.equal(root.gridApps[0].folderId,id);
  assert.equal(root.gridApps[root.gridApps.length-1].appId,'new');
}

{
  const {root,ctx,Qt} = fixture();
  ctx.DesktopEntries.applications.values=['A','B','C','D','E','F'].map(id=>({id,name:id,icon:'app'}));
  root.refreshGridCatalog(); root.filter='app'; root.usage={A:60,B:50,C:40,D:30,E:20,F:10};
  root.refresh(); root.gridSelectedId='app:B';
  const usage=JSON.stringify(root.usage);
  root.changeVisibility('hide','B');
  assert.equal(root.gridApps.map(a=>a.appId).join(','),'A,C,D,E,F');
  assert.equal(root.gridSelectedId,'app:C');
  assert.equal(ctx.layoutStore.order.join(','),'A,B,C,D,E,F');
  root.reorderGrid('app:F',0);
  assert.equal(ctx.layoutStore.order.join(','),'F,A,B,C,D,E');
  root.changeVisibility('restore','B');
  assert.equal(root.gridApps.map(a=>a.appId).join(','),'F,A,B,C,D,E');
  root.folderDrop('app:A','app:B');
  const folder=root.gridApps.find(a=>a.kind==='folder');
  root.openGridFolder(folder.folderId);
  root.changeVisibility('hide','B');
  assert.equal(root.folderApps.length,1);
  assert.equal(root.openFolderId,folder.folderId);
  assert.equal(root.folderSelectedId,'app:A');
  root.changeVisibility('hide','A');
  assert.equal(root.openFolderId,'');
  assert.equal(root.gridApps.some(a=>a.kind==='folder'),false);
  assert.equal(ctx.layoutStore.items.find(i=>i.type==='folder').apps.join(','),'B,A');
  root.changeVisibility('restore','A');
  root.openGridFolder(folder.folderId);
  assert.equal(root.folderApps.length,1);
  root.closeGridFolder(); root.folderDrop('app:C','folder:'+folder.folderId); root.openGridFolder(folder.folderId);
  root.reorderGrid('app:C',0);
  assert.equal(ctx.layoutStore.items.find(i=>i.type==='folder').apps.join(','),'B,C,A');
  root.changeVisibility('restore','B');
  assert.equal(root.folderApps.map(a=>a.appId).join(','),'B,C,A');
  root.changeVisibility('hide','B'); root.closeGridFolder(); root.performAction('deleteFolder');
  assert.equal(ctx.layoutStore.order.join(','),'F,B,C,A,D,E');
  assert.equal(ctx.layoutStore.hidden.join(','),'B');
  root.changeVisibility('hide','C');
  root.filter='all'; root.query=''; root.refresh();
  root.quickOpen=true; root.quickApps=root.frequentApps();
  root.changeVisibility('hide','A');
  assert.equal(root.quickOpen,false);
  assert.equal(root.frequentApps().map(a=>a.appId).join(','),'D,E,F');
  assert.equal(JSON.stringify(root.usage),usage);
  root.changeVisibility('restore','A');
  assert.equal(root.frequentApps()[0].appId,'A');
  root.filter='all'; root.query='A'; root.refresh();
  root.files=[{kind:'file',path:'/A',title:'A'}]; root.immediate.unshift({kind:'calc',title:'42'}); root.combine(false);
  const generation=root.generation;
  root.changeVisibility('hide','A');
  assert.equal(root.results.some(r=>r.kind==='app' && r.appId==='A'),false);
  assert.equal(root.results.some(r=>r.kind==='file'),true);
  assert.equal(root.results.some(r=>r.kind==='calc'),true);
  assert.equal(root.generation,generation,'visibility never restarts file search');
  root.filter='app'; root.query=''; root.refresh();
  assert.equal(root.results.some(r=>r.appId==='A'),false);
  root.handleKey({key:Qt.Key_H,modifiers:Qt.ControlModifier});
  assert.equal(root.hiddenOpen,true);
  root.handleEscape(); assert.equal(root.hiddenOpen,false); assert.equal(root.filter,'app');
  const structure=JSON.stringify(ctx.layoutStore.items);
  root.changeVisibility('restoreAll','');
  assert.equal(ctx.layoutStore.hidden.length,0);
  assert.equal(JSON.stringify(ctx.layoutStore.items),structure);
  assert.equal(JSON.stringify(root.usage),usage);
}
console.log('PASS: hide/restore across root/folders/search/circles, anchored edits, selection, management shortcut and usage preservation.');
{
  const {root, launched, saved} = fixture();
  root.launchApp({appId:'org.telegram.desktop', title:'Telegram'});
  assert.equal(launched[0], 'uwsm-app -- gtk-launch "org.telegram.desktop.desktop"', 'restore filename extension on exact Quickshell ID');
  assert.equal(saved[0]['org.telegram.desktop'], 1, 'usage retains the catalog ID');
  assert.equal(Object.hasOwn(saved[0], 'org.telegram.desktop.desktop'), false, 'launch filename never becomes persistent identity');
}
