// SPDX-License-Identifier: GPL-3.0-only
// Exercise the shipped QML's JavaScript, with process/UI effects replaced by fakes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const qml = fs.readFileSync(path.join(__dirname, '..', 'Spotlight.qml'), 'utf8');
const source = qml.slice(qml.indexOf('  function open('), qml.indexOf('  onQueryChanged:'));
function fixture() {
  const launched = [], saved = [];
  const root = {opened: true, query: '', filter: 'all', usage: {}, usageLoaded: true,
    quickApps: [], quickOpen: false, quickIndex: 0, actionsOpen: false, actionIndex: 0,
    immediate: [], files: [], results: [], selected: 0, generation: 0, appLibrary: null};
  Object.defineProperties(root, {
    expanded: {get: () => root.query.trim().length > 0 || root.filter !== 'all'},
    commandMode: {get: () => root.query.trim().startsWith('>')},
    current: {get: () => root.results[root.selected] || null},
    actions: {get: () => [{key:'open'}, {key:'copy'}]}
  });
  const Qt = {iconPath: x => x || 'fallback', ShiftModifier: 1, ControlModifier: 2};
  ['Escape','Tab','Backtab','Return','Enter','Left','Right','Down','Up','PageDown','PageUp']
    .forEach((name, i) => Qt['Key_' + name] = i + 10);
  const ctx = vm.createContext({root, Qt, Quickshell: Qt,
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
