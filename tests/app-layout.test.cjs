// SPDX-License-Identifier: GPL-3.0-only
const assert = require('node:assert/strict');
const L = require('../logic/AppLayout.js');
let checks = 0;
function equal(actual, expected) { assert.deepEqual(actual,expected); checks++; }
for (const [saved, available, expected] of [
  [[],['A','B','C'],['A','B','C']],
  [['C','A','B'],['A','B','C'],['C','A','B']],
  [['C','A','B'],['A','C'],['C','A']],
  [['C','A'],['A','B','C','D'],['C','A','B','D']],
  [['A','B','A','C','B'],['A','B','C'],['A','B','C']],
  [['unknown','C','A'],['A','B','C'],['C','A','B']],
  [['C','A'],[],[]],
  [[],['A','A','B'],['A','B']]
]) {
  const before = JSON.stringify(saved);
  equal(L.reconcile(saved,available),expected);
  equal(JSON.stringify(saved),before);
}
for (const [id,to,expected] of [
  ['C',0,['C','A','B','D']], ['A',3,['B','C','D','A']],
  ['B',2,['A','C','B','D']], ['D',0,['D','A','B','C']],
  ['B',1,['A','B','C','D']], ['missing',2,['A','B','C','D']],
  ['C',-5,['C','A','B','D']], ['A',99,['B','C','D','A']],
  ['A',NaN,['A','B','C','D']]
]) {
  const order = ['A','B','C','D'];
  equal(L.moveId(order,id,to),expected);
  equal(order,['A','B','C','D']);
}
equal(L.moveId([],'A',1),[]);
equal(L.moveId(['A'],'A',99),['A']);
equal(L.moveId(['A','B','A','C'],'A',2),['B','C','A']);
for (const raw of [undefined,null,'','  ']) equal(L.parse(raw),{items:[],hidden:[],error:false,protected:false,migrated:false});
for (const raw of ['bad','null','[]','1','true','{}','{"version":1}', '{"version":1,"order":{}}', '{"version":1,"order":[1]}', '{"version":1,"order":[""]}', '{"version":0,"order":[]}', '{"version":"1","order":[]}']) equal(L.parse(raw).error,true);
equal(L.parse('{"version":1,"order":["B","A","B"]}'),{items:['B','A'].map(L.appItem),hidden:[],error:false,protected:false,migrated:true});
for (const raw of ['{"version":999,"order":["example"]}', '{"version":999,"order":{}}']) {
  const parsed=L.parse(raw);
  equal(parsed.protected,true); equal(parsed.error,false); equal(parsed.items,[]);
  equal(L.maySave(true,parsed.protected,true),false);
}
equal(L.maySave(false,false,true),false);
equal(L.maySave(true,false,false),false);
equal(L.maySave(true,false,true),true);
equal(L.allAppIds(L.parse(L.serialize(['org.telegram.desktop','id with spaces','$(touch bad)','org.telegram.desktop'].map(L.appItem))).items),['org.telegram.desktop','id with spaces','$(touch bad)']);
equal(L.insertionTarget(0,3,true,4),3);
equal(L.insertionTarget(3,0,false,4),0);
equal(L.insertionTarget(1,1,false,4),1);
equal(L.insertionTarget(1,1,true,4),1);
// Exhaust all moves in a 300-item catalog: uniqueness, boundaries and identity.
const catalog=Array.from({length:300},(_,i)=>'app'+i);
for (const from of [0,1,149,298,299]) for (const to of [0,1,149,298,299]) {
  const moved=L.moveId(catalog,catalog[from],to);
  equal(moved[to],catalog[from]); equal(new Set(moved).size,300);
}
console.log(`PASS: ${checks} layout reconciliation, reorder, parsing and write-policy checks.`);
