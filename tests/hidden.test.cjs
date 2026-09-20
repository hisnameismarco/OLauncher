// SPDX-License-Identifier: GPL-3.0-only
const assert = require('node:assert/strict');
const L = require('../logic/AppLayout.js');
let checks=0;
function eq(actual,expected) { assert.deepEqual(actual,expected); checks++; }
const A=L.appItem, F=(apps,id='f')=>({type:'folder',id,name:'Development',apps});
const flat=(...ids)=>ids.map(A);
function visible(items,ids,hidden) { return L.filterVisibleLayout(L.reconcileWithHidden(items,ids,hidden),hidden); }
for (const [hidden,expected] of [[undefined,[]],[null,[]],['firefox',[]],[[],[]],[[12,null,'firefox','firefox',''],['firefox']],[['stale','org.telegram.desktop'],['stale','org.telegram.desktop']]]) {
  eq(L.parse(JSON.stringify({version:2,items:[],hidden})).hidden,expected);
}
eq(L.parse('{"version":1,"order":["A"]}').hidden,[]);
eq(L.changeHidden([],'hide','A'),['A']);
eq(L.changeHidden(['A'],'hide','A'),['A']);
eq(L.changeHidden(['A','stale'],'restore','A'),['stale']);
eq(L.changeHidden(['A'],'restore','missing'),['A']);
eq(L.changeHidden(['A','stale'],'restoreAll',''),[]);
eq(L.parse(L.serialize(flat('A'),['B','B',null])).hidden,['B']);
const items=[A('X'),F(['A','B','C']),A('Y')];
const original=JSON.stringify(items);
eq(visible(items,['X','A','B','C','Y'],['B']),[A('X'),F(['A','C']),A('Y')]);
eq(visible(items,['X','A','B','C','Y'],['B','C']),[A('X'),F(['A']),A('Y')]);
eq(visible(items,['X','A','B','C','Y'],['A','B','C']),flat('X','Y'));
eq(visible(items,['X','A','B','C','Y'],[]),items);
eq(JSON.stringify(items),original);
eq(visible(flat('A','B','C'),['A','B','C'],['B']),flat('A','C'));
eq(visible([F(['A','B'])],['A'],['B']),[F(['A'])],'missing hidden sibling preserves folder');
eq(visible([F(['A','B'])],[],['A','B']),[]);
eq(L.extendLayout(items,['new']),items.concat(A('new')));
eq(L.extendLayout(items,[]),items);
for (const [id,target,expected] of [
  ['D',0,['D','A','B','C']],['A',2,['B','C','D','A']],['C',0,['C','A','B','D']],
  ['A',1,['B','C','A','D']],['C',2,['A','B','D','C']],['C',1,['A','B','C','D']],
  ['missing',0,['A','B','C','D']],['D',-8,['D','A','B','C']],['A',99,['B','C','D','A']]
]) {
  const root=L.moveVisibleRoot(flat('A','B','C','D'),'app:'+id,target,['app:A','app:C','app:D']);
  eq(L.allAppIds(root),expected);
  const inside=L.moveVisibleInside([F(['A','B','C','D'])],'f',id,target,['A','C','D']);
  eq(inside[0].apps,expected);
  eq(L.filterVisibleLayout(root,['B']).map(i=>i.appId),expected.filter(i=>i!=='B'));
}
const mixed=[A('A'),F(['B','C'],'hidden-folder'),A('D'),F(['E','F'],'visible-folder')];
eq(L.moveVisibleRoot(mixed,'folder:visible-folder',0,['app:A','app:D','folder:visible-folder']),[F(['E','F'],'visible-folder'),A('A'),F(['B','C'],'hidden-folder'),A('D')]);
const deleted=L.deleteFolder(items,'f');
eq(deleted,flat('X','A','B','C','Y'));
eq(L.filterVisibleLayout(deleted,['B']),flat('X','A','C','Y'));
eq(L.removeAppFromFolder([F(['A','B'])],'f','A'),flat('B','A'));
eq(L.filterVisibleLayout(L.removeAppFromFolder([F(['A','B'])],'f','A'),['B']),flat('A'));
eq(L.addAppToFolder([F(['A','B']),A('C')],'C','f'),[F(['A','B','C'])]);
const results=[{kind:'app',appId:'A'},{kind:'file',path:'A'},{kind:'calc',title:'42'},{kind:'cmd',title:'A'},{kind:'app',appId:'B'}];
eq(L.filterAppResults(results,['A']),results.slice(1));
eq(L.filterAppResults(results,[]),results);
eq(L.filterAppResults(['A','B','C','D','E','F'].map(appId=>({kind:'app',appId})),['B','C']).slice(0,4).map(a=>a.appId),['A','D','E','F']);
// Exhaust target anchors across varying hidden positions. Nondragged order must never change.
const all=Array.from({length:20},(_,i)=>'id'+i);
for (const hidden of [['id1'],['id0','id19'],['id2','id4','id6']]) {
  const shown=all.filter(id=>!hidden.includes(id));
  for (const from of [0,Math.floor(shown.length/2),shown.length-1]) for (const to of [0,Math.floor(shown.length/2),shown.length-1]) {
    const moved=L.anchoredMove(all,shown,shown[from],to);
    eq(moved.filter(id=>!hidden.includes(id)),L.moveId(shown,shown[from],to));
    eq(moved.filter(id=>id!==shown[from]),all.filter(id=>id!==shown[from]));
    eq(new Set(moved).size,all.length);
  }
}
console.log(`PASS: ${checks} hidden-state normalization, projection, membership, anchors and visibility assertions.`);
