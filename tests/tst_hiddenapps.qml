// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtTest
import "../components"
Item {
  width: 680; height: 400
  TextInput { id: search; focus: true }
  HiddenAppsView {
    id: hidden
    y: 30; width: 640; height: 250
    apps: []; totalHidden: 0
    ink: "#302b2b"; selectionColor: "#263c3435"; uiFont: "sans-serif"
  }
  SignalSpy { id: restore; target: hidden; signalName: "restoreRequested" }
  SignalSpy { id: all; target: hidden; signalName: "restoreAllRequested" }
  TestCase {
    name: "HiddenAppsRuntime"
    when: windowShown
    function init() {
      hidden.apps=[{appId:"A",title:"App A",icon:""},{appId:"B",title:"App B",icon:""}]
      hidden.totalHidden=2; hidden.width=640; hidden.select(0)
      restore.clear(); all.clear(); search.forceActiveFocus(); wait(20)
    }
    function test_navigationRestoreAndRestoreAll() {
      hidden.moveSelection(1); hidden.activateSelected()
      compare(restore.signalArguments[0][0],"B")
      hidden.moveSelection(1); hidden.activateSelected()
      compare(all.count,1)
      hidden.moveSelection(1); compare(hidden.selectedIndex,2)
      hidden.moveSelection(-20); compare(hidden.selectedIndex,0)
      verify(search.activeFocus)
    }
    function test_openStartsOnFirstApp() {
      hidden.visible=false; hidden.select(2)
      hidden.visible=true
      compare(hidden.selectedKey,"app:A")
    }
    function test_restoreDuringReveal() {
      hidden.visible=false; hidden.visible=true
      hidden.activateSelected()
      compare(restore.signalArguments[0][0],"A")
      verify(search.activeFocus)
    }
    function test_clickAndFocus() {
      var list=findChild(hidden,"hiddenAppsList")
      mouseClick(list.itemAtIndex(1),80,20)
      compare(restore.signalArguments[0][0],"B")
      verify(search.activeFocus)
    }
    function test_removalSelectionAndEmpty() {
      hidden.select(1)
      hidden.apps=[hidden.apps[0]]; hidden.totalHidden=1
      compare(hidden.selectedKey,"action:restore-all")
      hidden.apps=[]; hidden.totalHidden=0
      compare(hidden.selectedIndex,-1)
      hidden.activateSelected(); compare(restore.count,0)
    }
    function test_staleOnlyRestoreAll() {
      hidden.apps=[]; hidden.totalHidden=3
      compare(hidden.rows.length,1)
      hidden.activateSelected(); compare(all.count,1)
    }
    function test_largeListScrollAndResize() {
      var apps=[]
      for (var i=0;i<300;i++) apps.push({appId:String(i),title:"App "+i,icon:""})
      hidden.apps=apps; hidden.totalHidden=300
      hidden.select(299); hidden.width=180
      var list=findChild(hidden,"hiddenAppsList")
      tryVerify(function() { return list.contentY>0 })
      compare(hidden.selectedKey,"app:299")
      hidden.activateSelected(); compare(restore.signalArguments[0][0],"299")
    }
  }
}
