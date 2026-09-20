// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtTest
import "../components"
import "../logic/AppLayout.js" as AppLayout

Item {
  width: 680; height: 500
  TextInput { id: input; focus: true }
  AppGrid {
    id: appGrid
    y: 40; width: 664; height: 264
    apps: []
    selectedIndex: 0
    property var storedIds: []
    ink: "#302b2b"
    selectionColor: "#263c3435"
    uiFont: "sans-serif"
    onDragSelected: function(id) { selectedIndex = apps.findIndex(function(a) { return (a.key || a.appId) === id }) }
    onReordered: function(id, target) {
      if (storedIds.length) storedIds = AppLayout.anchoredMove(storedIds,apps.map(function(a) { return a.appId }),id,target)
      var before = apps
      apps = AppLayout.moveId(apps.map(function(a) { return a.key || a.appId }), id, target).map(function(key) {
        return before.find(function(a) { return (a.key || a.appId) === key })
      })
      selectedIndex = apps.findIndex(function(a) { return (a.key || a.appId) === id })
    }
  }
  SignalSpy { id: activation; target: appGrid; signalName: "activated" }
  SignalSpy { id: contexts; target: appGrid; signalName: "contextRequested" }
  SignalSpy { id: folders; target: appGrid; signalName: "folderDropped" }
  SignalSpy { id: reorder; target: appGrid; signalName: "reordered" }
  TestCase {
    name: "AppGridRuntime"
    when: windowShown
    function init() {
      appGrid.storedIds = []
      var apps = []
      for (var i = 0; i < 300; i++) apps.push({appId:"id-" + i, title:"App " + i, icon:""})
      appGrid.width = 664
      appGrid.apps = apps
      appGrid.selectedIndex = 0
      input.forceActiveFocus()
      activation.clear()
      reorder.clear()
      folders.clear()
      contexts.clear()
      appGrid.folderTargetsEnabled = false
      wait(30) // Settle model replacement before acquiring a pointer grab.
    }
    function test_pointerReorderPreservesHiddenRecord() {
      appGrid.storedIds=["A","B","C","D"]
      appGrid.apps=["A","C","D"].map(function(id) { return {appId:id,title:id,icon:""} })
      wait(30)
      var view=findChild(appGrid,"applicationGrid")
      var start=view.itemAtIndex(2).mapToItem(appGrid,30,30)
      mousePress(appGrid,start.x,start.y)
      mouseMove(appGrid,2,30,30)
      mouseRelease(appGrid,2,30)
      compare(reorder.count,1)
      compare(appGrid.storedIds.join(","),"D,A,B,C")
      compare(appGrid.apps.map(function(a) { return a.appId }).join(","),"D,A,C")
      compare(appGrid.selectedIndex,0)
    }
    function test_hiddenChildReorderUsesFullMembership() {
      // Folder contents use the same AppGrid in reorder-only mode.
      appGrid.storedIds=["A","B","C","D"]
      appGrid.apps=["A","C","D"].map(function(id) { return {appId:id,title:id,icon:""} })
      wait(30)
      var view=findChild(appGrid,"applicationGrid")
      mousePress(appGrid,30,30)
      mouseMove(appGrid,view.cellWidth*3-2,30,30)
      mouseRelease(appGrid,view.cellWidth*3-2,30)
      compare(reorder.count,1)
      compare(appGrid.storedIds.join(","),"B,C,D,A")
      compare(appGrid.apps.map(function(a) { return a.appId }).join(","),"C,D,A")
      verify(!appGrid.folderArmed)
    }
    function test_revealNeverBlocksActivation() {
      appGrid.visible=false
      appGrid.visible=true
      var view=findChild(appGrid,"applicationGrid")
      mouseClick(view.itemAtIndex(0),30,30)
      compare(activation.count,1)
      verify(input.activeFocus)
    }
    function test_repeatedRevealResizeAndScrollStaysVirtualized() {
      var view=findChild(appGrid,"applicationGrid")
      for (var i=0;i<40;i++) {
        appGrid.visible=false; appGrid.visible=true
        appGrid.width=i%2 ? 304 : 664
        appGrid.selectedIndex=(i*17)%300
        wait(5)
      }
      tryVerify(function() { return view.contentItem.children.length<100 })
      compare(view.currentIndex,appGrid.selectedIndex)
      verify(input.activeFocus)
    }
    function test_resizeKeepsSelectionVisible() {
      var view = findChild(appGrid, "applicationGrid")
      appGrid.selectedIndex = 299
      appGrid.width = 304
      tryCompare(appGrid, "columns", 2)
      tryVerify(function() {
        var item = view.itemAtIndex(299)
        return item && item.y >= view.contentY && item.y + item.height <= view.contentY + view.height
      })
      compare(view.currentIndex, 299)
      // GridView instantiates the viewport and a small buffer, not all 300 cells.
      verify(view.contentItem.children.length < 100)
    }
    function test_clickEmitsIdentityAndKeepsSearchFocus() {
      var view = findChild(appGrid, "applicationGrid")
      tryVerify(function() { return view.itemAtIndex(0) !== null })
      mouseClick(view.itemAtIndex(0), 30, 30)
      compare(activation.count, 1)
      compare(activation.signalArguments[0][0], "id-0")
      verify(input.activeFocus)
      keyClick(Qt.Key_F)
      keyClick(Qt.Key_I)
      keyClick(Qt.Key_R)
      keyClick(Qt.Key_E)
      compare(input.text, "fire")
      input.clear()
    }
    function test_pointerDragReordersOnce() {
      var view = findChild(appGrid, "applicationGrid")
      tryVerify(function() { return view.itemAtIndex(0) !== null })
      var start = view.itemAtIndex(0).mapToItem(appGrid, 30, 30)
      mousePress(appGrid, start.x, start.y)
      mouseMove(appGrid, start.x + 3, start.y)
      verify(!appGrid.dragging, "movement below threshold is not a drag")
      mouseMove(appGrid, 200, start.y, 30)
      tryCompare(appGrid, "dragging", true)
      compare(reorder.count, 0, "pointer movement never commits")
      compare(appGrid.apps[0].appId, "id-0")
      mouseRelease(appGrid, 200, start.y)
      compare(reorder.count, 1)
      compare(appGrid.apps[1].appId, "id-0")
      compare(appGrid.selectedIndex, 1)
      compare(activation.count, 0, "drag release never launches")
    }
    function test_outsideDropCancels() {
      var view = findChild(appGrid, "applicationGrid")
      tryVerify(function() { return view.itemAtIndex(0) !== null })
      var start = view.itemAtIndex(0).mapToItem(appGrid, 30, 30)
      mousePress(appGrid, start.x, start.y)
      mouseMove(appGrid, 150, start.y, 30)
      tryCompare(appGrid, "dragging", true)
      mouseRelease(appGrid, -10, start.y)
      compare(reorder.count, 0)
      compare(appGrid.apps[0].appId, "id-0")
      verify(!appGrid.dragging)
      compare(activation.count, 0)
    }
    function test_interruptedDragCancels() {
      appGrid.beginDrag("id-0", Qt.point(30,30))
      appGrid.updateDrag(Qt.point(200,30))
      appGrid.visible = false
      appGrid.finishDrag(Qt.point(200,30))
      compare(reorder.count, 0)
      appGrid.visible = true
      appGrid.beginDrag("id-0", Qt.point(30,30))
      appGrid.apps = appGrid.apps.slice(1)
      verify(!appGrid.dragging)
      compare(reorder.count, 0)
    }
    function test_scrolledDragAndResize() {
      var view = findChild(appGrid, "applicationGrid")
      appGrid.selectedIndex = 290
      tryVerify(function() {
        var cell = view.itemAtIndex(290)
        return cell && cell.y >= view.contentY && cell.y + cell.height <= view.contentY + view.height
      })
      var cell = view.itemAtIndex(290)
      var start = cell.mapToItem(appGrid, 30, 30)
      var targetCell = view.itemAtIndex(289)
      var target = targetCell.mapToItem(appGrid, 10,30)
      mousePress(appGrid, start.x,start.y)
      mouseMove(appGrid, target.x,target.y,30)
      mouseRelease(appGrid,target.x,target.y)
      compare(reorder.count,1)
      compare(appGrid.apps[289].appId,"id-290")
      compare(appGrid.selectedIndex,289)
      appGrid.width=304
      tryVerify(function() {
        var item=view.itemAtIndex(289)
        return item && item.y>=view.contentY && item.y+item.height<=view.contentY+view.height
      })
      compare(appGrid.apps[289].appId,"id-290")
    }
    function test_wheelDuringDragKeepsSource() {
      var view = findChild(appGrid, "applicationGrid")
      tryVerify(function() { return view.itemAtIndex(0) !== null })
      wait(30)
      var start = view.itemAtIndex(0).mapToItem(appGrid,30,30)
      mousePress(appGrid,start.x,start.y)
      mouseMove(appGrid,200,start.y,30)
      tryCompare(appGrid,"dragging",true)
      var before = view.contentY
      mouseWheel(view,200,50,0,-1200)
      tryVerify(function() { return view.contentY > before + view.height })
      verify(appGrid.dragging)
      compare(reorder.count,0)
      mouseRelease(appGrid,200,50)
      compare(reorder.count,1)
      verify(appGrid.selectedIndex>5)
      compare(appGrid.apps[appGrid.selectedIndex].appId,"id-0")
    }
    function test_deliberateCenterDropCreatesFolderRequest() {
      appGrid.folderTargetsEnabled = true
      var view = findChild(appGrid,"applicationGrid")
      tryVerify(function() { return view.itemAtIndex(1) !== null })
      wait(30)
      var start=view.itemAtIndex(0).mapToItem(appGrid,30,30)
      var target=view.itemAtIndex(1).mapToItem(appGrid,view.cellWidth/2,30)
      mousePress(appGrid,start.x,start.y)
      mouseMove(appGrid,target.x,target.y,30)
      compare(folders.count,0)
      tryCompare(appGrid,"folderArmed",true)
      compare(appGrid.dropMode,"folder-create")
      mouseRelease(appGrid,target.x,target.y)
      compare(folders.count,1)
      compare(folders.signalArguments[0][0],"id-0")
      compare(folders.signalArguments[0][1],"id-1")
      compare(reorder.count,0)
    }
    function test_folderClickAndContextUseFolderIdentity() {
      appGrid.apps=[{key:"folder:f",folderId:"f",kind:"folder",title:"Folder",preview:[]}]
      wait(30)
      var view=findChild(appGrid,"applicationGrid")
      mouseClick(view.itemAtIndex(0),30,30)
      compare(activation.count,1)
      compare(activation.signalArguments[0][0],"folder:f")
      mouseClick(view.itemAtIndex(0),30,30,Qt.RightButton)
      compare(contexts.count,1)
      compare(contexts.signalArguments[0][0],"folder:f")
    }
    function test_quickCenterPassStillInserts() {
      appGrid.folderTargetsEnabled=true
      appGrid.beginDrag("id-0",Qt.point(30,30))
      appGrid.finishDrag(Qt.point(appGrid.width/appGrid.columns*1.5,30))
      compare(folders.count,0)
      compare(reorder.count,1)
    }
    function test_addToFolderAndNoNestedFolderTarget() {
      appGrid.folderTargetsEnabled=true
      appGrid.apps=[{appId:"A",title:"A",icon:"",kind:"app"},
        {key:"folder:f",folderId:"f",kind:"folder",title:"Folder",preview:[]}]
      wait(30)
      var target=Qt.point(appGrid.width/appGrid.columns*1.5,30)
      appGrid.beginDrag("A",target)
      tryCompare(appGrid,"folderArmed",true)
      compare(appGrid.dropMode,"folder-add")
      appGrid.finishDrag(target)
      compare(folders.count,1)
      appGrid.beginDrag("folder:f",Qt.point(30,30))
      wait(450)
      verify(!appGrid.folderArmed)
      appGrid.finishDrag(Qt.point(30,30))
      compare(folders.count,1)
      compare(reorder.count,1)
    }
    function test_leavingCenterAndScrollingDisarmFolderTarget() {
      appGrid.folderTargetsEnabled=true
      var view=findChild(appGrid,"applicationGrid")
      wait(30)
      var center=Qt.point(view.cellWidth*1.5,30)
      appGrid.beginDrag("id-0",center)
      tryCompare(appGrid,"folderArmed",true)
      appGrid.updateDrag(Qt.point(view.cellWidth+5,30))
      verify(!appGrid.folderArmed)
      appGrid.updateDrag(center)
      tryCompare(appGrid,"folderArmed",true)
      view.contentY += 88
      verify(!appGrid.folderArmed)
      appGrid.cancelDrag()
      compare(folders.count,0)
    }
    function test_wheelScrolls() {
      var view = findChild(appGrid, "applicationGrid")
      tryVerify(function() {
        var item = view.itemAtIndex(0)
        return item && item.y >= view.contentY && item.y < view.contentY + view.height
      })
      wait(30) // Let deferred layout/selection positioning finish before scrolling.
      var before = view.contentY
      mouseWheel(view, 50, 50, 0, -120)
      tryVerify(function() { return view.contentY > before })
    }
  }
}
