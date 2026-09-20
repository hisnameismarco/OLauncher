// SPDX-License-Identifier: GPL-3.0-only
const assert = require('node:assert/strict');
const L = require('../logic/AppLayout.js');
let checks = 0;
function eq(actual, expected) { assert.deepEqual(actual,expected); checks++; }
const A = L.appItem;
const F = (id, apps, name='Folder') => ({type:'folder',id,name,apps});
const flat = (...ids) => ids.map(A);
function operation(items, name, args, expected) {
  const before=JSON.stringify(items), result=L.operate(items,name,args);
  eq(result,expected); eq(JSON.stringify(items),before);
  eq(L.normalizeLayout(result),result);
  const ids=L.allAppIds(result); eq(new Set(ids).size,ids.length);
  return result;
}
for (const order of [[],['A','B','C'],['A','B','A'],['stale','org.telegram.desktop']]) {
  const parsed=L.parse(JSON.stringify({version:1,order}));
  eq(parsed.migrated,true); eq(parsed.error,false);
  eq(parsed.items,L.uniqueIds(order).map(A));
  const twice=L.parse(L.serialize(parsed.items));
  eq(twice.migrated,false); eq(twice.items,parsed.items);
}
eq(L.parse('{"version":999,"items":[]}').protected,true);
eq(L.parse('{"version":999,"items":[]}').migrated,false);
eq(L.parse('{"version":1,"order":["A",42]}').error,true);
eq(L.parse('{"version":2,"items":{}}').error,true);
for (const [input,expected] of [
  [[A('A'),A('A')],flat('A')],
  [[A('A'),F('f',['A','B','C'])],[A('A'),F('f',['B','C'])]],
  [[F('f',['A','B']),A('A')],[F('f',['A','B'])]],
  [[F('f',['A','B']),F('g',['B','C','D'])],[F('f',['A','B']),F('g',['C','D'])]],
  [[F('f',['A','B']),F('f',['C','D'])],[F('f',['A','B'])]],
  [[{type:'unknown',appId:'A'},null,{type:'app',appId:4}],[]],
  [[F('f',[F('nested',['A','B'])])],[]],
  [[F('f',[])],[]],
  [[F('f',['A'])],flat('A')],
  [[F('f',['A','A','B'])],[F('f',['A','B'])]],
  [[F('f',['A','B'],'   ')],[F('f',['A','B'])]],
  [[F('f',['A','B'],42)],[]]
]) { eq(L.normalizeLayout(input),expected); eq(L.normalizeLayout(expected),expected); }
const created=operation(flat('A','B','C'),'create',['A','B','f'],[F('f',['B','A']),A('C')]);
operation(flat('A','B','C'),'create',['C','A','f'],[F('f',['A','C']),A('B')]);
operation(flat('X','A','Y','B','Z'),'create',['A','B','f'],[A('X'),A('Y'),F('f',['B','A']),A('Z')]);
for (const args of [['A','A','f'],['missing','B','f'],['A','missing','f'],['A','B','']]) operation(flat('A','B'),'create',args,flat('A','B'));
operation([A('A'),A('B'),F('f',['C','D'])],'create',['A','B','f'],[A('A'),A('B'),F('f',['C','D'])]);
const added=operation(created,'add',['C','f'],[F('f',['B','A','C'])]);
operation(added,'add',['B','f'],added);
operation(added,'add',['missing','f'],added);
operation(created,'add',['C','missing'],created);
operation(added,'remove',['f','A'],[F('f',['B','C']),A('A')]);
operation([A('X'),F('f',['A','B']),A('Z')],'remove',['f','A'],flat('X','B','A','Z'));
operation([F('f',['A'])],'remove',['f','A'],flat('A'));
operation(added,'remove',['f','missing'],added);
operation(added,'rename',['f','  Development  '],[F('f',['B','A','C'],'Development')]);
operation(added,'rename',['f','   '],added);
operation(added,'rename',['f','x'.repeat(90)],[F('f',['B','A','C'],'x'.repeat(64))]);
operation(added,'rename',['f','<b>$(echo hi)</b>'],[F('f',['B','A','C'],'<b>$(echo hi)</b>')]);
operation([A('A'),F('f',['X','Y','Z']),A('B')],'delete',['f'],flat('A','X','Y','Z','B'));
const mixed=[A('A'),F('f',['B','C']),A('D'),F('g',['E','F'])];
operation(mixed,'move',['folder:g',0],[F('g',['E','F']),A('A'),F('f',['B','C']),A('D')]);
operation(mixed,'move',['app:A',3],[F('f',['B','C']),A('D'),F('g',['E','F']),A('A')]);
operation(added,'inside',['f','C',0],[F('f',['C','B','A'])]);
operation(added,'inside',['f','B',99],[F('f',['A','C','B'])]);
operation(added,'inside',['f','C',-1],[F('f',['C','B','A'])]);
operation(added,'inside',['f','missing',0],added);
for (const [available,expected] of [
  [['A','B','C','D','E','F'],mixed],
  [['A','C','D','E','F'],[A('A'),A('C'),A('D'),F('g',['E','F'])]],
  [['B','C','D','E','F','new'],[F('f',['B','C']),A('D'),F('g',['E','F']),A('new')]],
  [[],[]]
]) {
  const before=JSON.stringify(mixed);
  eq(L.reconcileLayout(mixed,available),expected); eq(JSON.stringify(mixed),before);
}
eq(L.itemKey(A('folder:f')) === L.itemKey(F('f',['A','B'])),false,'typed keys cannot collide');
console.log(`PASS: ${checks} folder, v2 migration, invariants and reconciliation assertions.`);
