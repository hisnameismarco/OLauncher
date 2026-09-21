// SPDX-License-Identifier: GPL-3.0-only
const assert = require('node:assert/strict');
const G = require('../logic/GridNavigation.js');
let checks = 0;
function equal(actual, expected) { assert.deepEqual(actual, expected); checks++; }
for (const [index, direction, expected] of [
  [0,'left',0],[0,'right',1],[0,'up',0],[0,'down',4],
  [3,'right',4],[4,'left',3],[5,'up',1],[5,'down',9],
  [6,'down',9],[7,'down',9],[8,'down',8],[9,'down',9],
  [9,'right',9],[9,'up',5],[9,'left',8],[3,'up',3]
]) equal(G.move(index,10,4,direction),expected);
for (const direction of ['left','right','up','down','pageUp','pageDown']) {
  equal(G.move(-1,0,4,direction),-1);
  equal(G.move(0,1,4,direction),0);
}
equal(G.move(5,10,3,'down'),8);
equal(G.move(5,10,2,'up'),3);
equal(G.move(99,10,4,'left'),8);
equal(G.move(0,300,4,'pageDown'),12);
equal(G.move(299,300,4,'pageUp'),287);
for (const [width, columns] of [[0,1],[80,1],[208,2],[320,3],[562,5],[664,5],[1200,5]]) equal(G.columnsForWidth(width),columns);
for (const value of [undefined,null,'','invalid','[]','null','1','true','{}','{"filter":"app"}','{"filter":"unknown"}',[],42,{}, {filter:42}]) equal(G.payloadFilter(value),'all');
equal(G.payloadFilter('{"filter":"apps"}'),'app');
equal(G.payloadFilter({filter:'apps'}),'app');
for (const [filter,query,expected] of [['app','',true],['app','  ',true],['app','fire',false],['all','',false],['file','',false],['calc','',false]]) equal(G.isGrid(filter,query),expected);
const apps = [{appId:'b',title:'Same'}, {appId:'a',title:'Same'}, {appId:'c',title:'Alpha'}].sort(G.compareApps);
equal(apps.map(a => a.appId),['c','a','b']);
equal(G.selectionId(apps,'a',0),'a');
equal(G.selectionId(apps,'missing',99),'b');
equal(G.selectionId(apps,'missing',-1),'c');
equal(G.selectionId([],'a',0),'');
console.log(`PASS: ${checks} grid navigation, payload, mode, ordering and selection checks.`);
