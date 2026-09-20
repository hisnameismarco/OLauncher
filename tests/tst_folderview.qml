// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtTest
import "../components"

Item {
  width: 680; height: 500
  TextInput { id: search; focus: true }
  AppFolderView {
    id: folder
    y: 40; width: 664; height: 300
    folderName: "Development"
    apps: [{key:"app:A",appId:"A",kind:"app",title:"App A",icon:""},
      {key:"app:B",appId:"B",kind:"app",title:"App B",icon:""}]
    selectedIndex: 0
    ink: "#302b2b"; selectionColor: "#263c3435"; uiFont: "sans-serif"
    onEditCanceled: search.forceActiveFocus()
    onRenamed: search.forceActiveFocus()
  }
  SignalSpy { id: renamed; target: folder; signalName: "renamed" }
  SignalSpy { id: canceled; target: folder; signalName: "editCanceled" }
  SignalSpy { id: activation; target: folder; signalName: "activated" }
  SignalSpy { id: context; target: folder; signalName: "contextRequested" }
  SignalSpy { id: reordered; target: folder; signalName: "reordered" }
  TestCase {
    name: "FolderViewRuntime"
    when: windowShown
    function init() {
      folder.cancelRename(); folder.cancelDrag()
      folder.width=664; folder.selectedIndex=0
      renamed.clear(); canceled.clear(); activation.clear(); context.clear(); reordered.clear()
      search.text=""; search.forceActiveFocus()
      wait(30)
    }
    function test_revealAndCloseKeepInputFocus() {
      folder.visible=false; folder.visible=true
      var view=findChild(folder,"applicationGrid")
      mouseClick(view.itemAtIndex(0),30,30)
      compare(activation.count,1)
      folder.beginRename(); verify(!search.activeFocus)
      folder.visible=false
      verify(search.activeFocus)
      verify(!folder.editing)
      folder.visible=true
    }
    function test_inlineRenameCommitAndCancel() {
      var editor=findChild(folder,"folderNameEditor")
      folder.beginRename()
      verify(editor.activeFocus)
      editor.text=" Work "
      keyClick(Qt.Key_Return)
      compare(renamed.count,1)
      compare(renamed.signalArguments[0][0]," Work ")
      verify(search.activeFocus)
      folder.beginRename(); editor.text="Discard"
      keyClick(Qt.Key_Escape)
      verify(!folder.editing)
      compare(renamed.count,1)
      compare(canceled.count,1)
      verify(search.activeFocus)
    }
    function test_clickContextAndTypingFocus() {
      var view=findChild(folder,"applicationGrid")
      mouseClick(view.itemAtIndex(0),30,30)
      compare(activation.count,1)
      compare(activation.signalArguments[0][0],"app:A")
      mouseClick(view.itemAtIndex(1),30,30,Qt.RightButton)
      compare(context.count,1)
      compare(context.signalArguments[0][0],"app:B")
      verify(search.activeFocus)
      keyClick(Qt.Key_F)
      compare(search.text,"f")
    }
    function test_insideDragIsReorderOnlyAndResize() {
      var view=findChild(folder,"applicationGrid")
      var grid=view.parent
      var start=view.itemAtIndex(1).mapToItem(grid,30,30)
      mousePress(grid,start.x,start.y)
      mouseMove(grid,view.cellWidth/2,30,30)
      wait(450)
      verify(!grid.folderArmed)
      mouseRelease(grid,view.cellWidth/2,30)
      compare(reordered.count,1)
      compare(reordered.signalArguments[0][0],"app:B")
      compare(reordered.signalArguments[0][1],0)
      folder.width=180; folder.selectedIndex=1
      tryCompare(folder,"columns",1)
      tryVerify(function() { var item=view.itemAtIndex(1); return item && item.y>=view.contentY && item.y+item.height<=view.contentY+view.height })
    }
  }
}
