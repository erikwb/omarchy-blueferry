pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.weirdware.blueferry"
  ipcTarget: "io.weirdware.blueferry"
  manageIpc: false

  property bool componentsInstalled: false
  property bool configured: false
  property bool connected: false
  property var backendStatus: ({})
  property var threads: []
  property string statusMessage: ""
  property bool statusMessageIsError: false
  property bool cursorActive: false
  property bool cursorFromMouse: false
  property int rowIndex: 0
  property int statusRequestId: 0
  property int threadsRequestId: 0
  property var replyControllers: ({})
  property Item activeReplyRow: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string summary: !componentsInstalled ? "Not installed"
    : !configured ? "Setup required"
    : backendStatus.initializing === true ? "Starting"
    : connected ? "Connected" : "Reconnecting"
  readonly property var recentThreads: {
    var unread = []
    for (var index = 0; index < threads.length; ++index) {
      if (threadIsUnread(threads[index])) unread.push(threads[index])
      if (unread.length >= 5) break
    }
    return unread
  }

  // Refresh row data without replacing the editors or their keyboard focus.
  onRecentThreadsChanged: syncUnreadRows()
  Component.onCompleted: syncUnreadRows()

  function syncUnreadRows() {
    if (!recentThreads || !unreadModel) return
    if (activeReplyRow && !recentThreads.some(thread => thread.key === activeReplyRow.thread.key))
      closeReply()
    for (var index = 0; index < recentThreads.length; ++index) {
      var thread = recentThreads[index]
      var existing = index
      while (existing < unreadModel.count && unreadModel.get(existing).threadKey !== thread.key)
        existing++
      if (existing === unreadModel.count)
        unreadModel.insert(index, {threadKey: thread.key, thread: thread})
      else {
        if (existing !== index) unreadModel.move(existing, index, 1)
        unreadModel.setProperty(index, "thread", thread)
      }
    }
    if (unreadModel.count > recentThreads.length)
      unreadModel.remove(recentThreads.length, unreadModel.count - recentThreads.length)
    for (var key in replyControllers) {
      var controller = replyControllers[key]
      if (!controller.sending && controller.text === "" && controller.thread)
        controller.selectThread(controller.thread)
    }
  }

  function controllerFor(thread) {
    var key = "$" + thread.key
    if (!replyControllers[key]) {
      var controller = replyControllerComponent.createObject(root)
      controller.selectThread(thread)
      replyControllers[key] = controller
    }
    return replyControllers[key]
  }

  function requestStatus() {
    if (!componentsInstalled || statusRequestId !== 0) return
    statusRequestId = backendBridge.request("status", {})
  }

  function requestThreads() {
    if (!componentsInstalled || threadsRequestId !== 0) return
    threadsRequestId = backendBridge.request("threads", {limit: 50})
  }

  function refresh() {
    if (!installationProcess.running) installationProcess.running = true
    if (!componentsInstalled) return
    if (!configurationProcess.running) configurationProcess.running = true
    requestStatus()
    requestThreads()
  }

  function openClient(thread) {
    if (!componentsInstalled) {
      showInstallInstructions()
      return
    }
    var args = ["/usr/bin/blueferry-quickshell"]
    if (thread && thread.key)
      args = args.concat(["--thread", String(thread.key)])
    Quickshell.execDetached(args)
    root.close()
  }

  function openReply(thread) {
    for (var index = 0; index < unreadRows.count; ++index) {
      var row = unreadRows.itemAt(index)
      if (row.thread.key === thread.key) {
        row.focusEditor()
        return
      }
    }
  }

  function closeReply() {
    activeReplyRow = null
    keyCatcher.forceActiveFocus()
  }

  function showReplyRow(row) {
    var top = row.mapToItem(column, 0, 0).y
    var bottom = top + row.height
    var offset = Math.min(top, Math.max(viewport.contentY, bottom - viewport.height))
    viewport.contentY = Math.max(0, Math.min(offset, viewport.contentHeight - viewport.height))
  }

  function showInstallInstructions() {
    var command = "cd \"$HOME\"; printf '%s\\n' '' "
      + "'BlueFerry is not installed yet.' '' "
      + "'Install it from its source repository:' '' "
      + "'  mkdir -p ~/src' "
      + "'  git clone https://github.com/erikwb/blueferry.git ~/src/blueferry' "
      + "'  cd ~/src/blueferry' "
      + "'  ./build.sh -si' '' "
      + "'After installation, open this panel again to pair the iPhone.' ''; "
      + "exec \"${SHELL:-/bin/bash}\""
    Quickshell.execDetached(["xdg-terminal-exec", "bash", "-lc", command])
  }

  function threadIsUnread(thread) {
    if (!thread) return false
    if (thread.unread === true) return true
    if (thread.unread === false) return false
    var messages = thread.messages || []
    for (var index = 0; index < messages.length; ++index) {
      if (!messages[index].outgoing && messages[index].read === false) return true
    }
    return false
  }

  function threadIsStarred(thread) {
    return !!(thread && thread.starred === true)
  }

  function preview(thread) {
    if (!thread || !thread.messages || thread.messages.length === 0) return "No messages"
    var message = thread.messages[thread.messages.length - 1]
    return (message.outgoing ? "You: " : "") + String(message.body || "")
  }

  function previewTimestamp(thread) {
    if (!thread || !thread.messages || thread.messages.length === 0) return ""
    var message = thread.messages[thread.messages.length - 1]
    return String(message.display_timestamp || "")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (root.opened) {
    cursorActive = false
    rowIndex = 0
    refresh()
    Qt.callLater(function() {
      if (activeReplyRow) activeReplyRow.focusEditor()
      else keyCatcher.forceActiveFocus()
    })
  }

  Process {
    id: installationProcess
    command: ["/usr/bin/sh", "-c",
      "test -x /usr/bin/blueferry && test -x /usr/bin/blueferry-quickshell && test -x /usr/bin/blueferry-quickshell-bridge && printf ready"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var wasInstalled = root.componentsInstalled
        root.componentsInstalled = String(text).trim() === "ready"
        if (root.componentsInstalled && !wasInstalled) Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: configurationProcess
    command: ["/usr/bin/blueferry", "pairing-configuration-json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var status = JSON.parse(text)
          root.configured = status.configured === true
        } catch (error) { root.configured = false }
      }
    }
  }

  BackendBridge {
    id: backendBridge
    active: root.componentsInstalled
  }

  ListModel { id: unreadModel; dynamicRoles: true }

  // Controllers outlive unread-row delegates, retaining drafts and sends
  // even when another client marks a thread read or a refresh removes it.
  Component {
    id: replyControllerComponent
    ReplyController {
      bridge: backendBridge
      threads: root.threads
      connected: root.connected
    }
  }

  Connections {
    target: backendBridge

    function onResponse(method, requestId, resultJson) {
      if (method === "send_to_thread") {
        for (var key in root.replyControllers) {
          if (root.replyControllers[key].handleResponse(method, requestId)) {
            root.requestThreads()
            return
          }
        }
      }
      if (method === "status" && requestId === root.statusRequestId) {
        root.statusRequestId = 0
        var parsedStatus
        try {
          parsedStatus = JSON.parse(resultJson)
        } catch (error) {
          root.connected = false
          root.statusMessage = "BlueFerry status is temporarily unavailable"
          root.statusMessageIsError = true
          return
        }
        if (typeof parsedStatus !== "object" || parsedStatus === null
            || Array.isArray(parsedStatus)) {
          root.connected = false
          root.statusMessage = "BlueFerry status is temporarily unavailable"
          root.statusMessageIsError = true
          return
        }
        root.backendStatus = parsedStatus
        root.connected = parsedStatus.daemon === true && parsedStatus.map === true
        root.statusMessage = String(parsedStatus.connectivity_detail || "")
        root.statusMessageIsError = false
      } else if (method === "threads" && requestId === root.threadsRequestId) {
        root.threadsRequestId = 0
        try {
          var parsedThreads = JSON.parse(resultJson)
          root.threads = Array.isArray(parsedThreads) ? parsedThreads : []
        } catch (error) { root.threads = [] }
        root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.recentThreads.length))
      }
    }

    function onFailure(method, requestId, message) {
      for (var key in root.replyControllers)
        root.replyControllers[key].handleFailure(method, requestId, message)
      if (method === "status" || method === "") {
        if (method === "" || requestId === root.statusRequestId)
          root.statusRequestId = 0
        root.connected = false
        if (root.configured) {
          root.statusMessage = message || "Unable to contact BlueFerry"
          root.statusMessageIsError = true
        }
      }
      if (method === "threads" || method === "") {
        if (method === "" || requestId === root.threadsRequestId)
          root.threadsRequestId = 0
        root.threads = []
      }
    }

    function onEventReceived(name, _data) {
      if (name === "status-changed") root.requestStatus()
      else if (name === "history-changed") root.requestThreads()
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string { return root.summary }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏲"
    dimmed: !root.connected
    tooltipText: "iPhone: " + root.summary
    onPressed: {
      if (root.componentsInstalled) root.toggle()
      else root.showInstallInstructions()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.activeReplyRow ? root.activeReplyRow.focusTarget : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.activeReplyRow !== null && root.activeReplyRow.activeFocus
      onMoveRequested: function(_dx, dy) {
        root.cursorActive = true
        root.cursorFromMouse = false
        root.rowIndex = Math.max(0, Math.min(root.recentThreads.length, root.rowIndex + dy))
      }
      onActivateRequested: {
        if (root.rowIndex < root.recentThreads.length)
          root.openReply(root.recentThreads[root.rowIndex])
        else
          root.openClient()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "iPhone"
            meta: root.summary.toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.connected ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: "󰏲"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.statusMessage !== ""
            width: parent.width
            text: root.statusMessage
            color: root.statusMessageIsError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.configured
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Messages"; value: root.backendStatus.map ? "Connected" : "Unavailable" }
            InfoPair { label: "Contacts"; value: root.backendStatus.pbap ? "Connected" : "Unavailable" }
            InfoPair { label: "Notifications"; value: root.backendStatus.ancs ? "Connected" : "Unavailable" }
          }

          PanelSeparator {
            visible: root.configured
            foreground: root.foreground
          }

          Column {
            visible: root.recentThreads.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "UNREAD"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              id: unreadRows
              model: unreadModel
              RecentRow {
                required property int index
                width: parent.width
                cursorIndex: index
              }
            }
          }

          CursorSurface {
            id: openRow
            width: parent.width
            implicitHeight: openText.implicitHeight + Style.spacing.rowPaddingX
            hasCursor: root.cursorActive && root.rowIndex === root.recentThreads.length
            foreground: root.foreground

            Text {
              id: openText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              text: root.configured ? "Open messages and settings  →" : "Set up iPhone  →"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.cursorActive = true
                root.cursorFromMouse = true
                root.rowIndex = root.recentThreads.length
              }
              onExited: if (root.cursorFromMouse && root.rowIndex === root.recentThreads.length)
                root.cursorActive = false
              onClicked: root.openClient()
            }
          }
        }
      }
    }
  }

  component RecentRow: FocusScope {
    id: row
    required property var thread
    property int cursorIndex: 0
    readonly property Item focusTarget: inlineReply.focusTarget
    objectName: "threadRow:" + thread.key
    implicitHeight: content.implicitHeight
    onCursorIndexChanged: if (activeFocus) root.rowIndex = cursorIndex
    Keys.onEscapePressed: root.closeReply()
    onActiveFocusChanged: if (activeFocus) {
      root.activeReplyRow = row
      root.rowIndex = cursorIndex
      Qt.callLater(function() { root.showReplyRow(row) })
    }

    function focusEditor() {
      inlineReply.focusEditor()
      root.showReplyRow(row)
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(6)

      CursorSurface {
        objectName: "threadHeader"
        width: parent.width
        implicitHeight: heading.implicitHeight + Style.spacing.rowPaddingX
        hasCursor: root.cursorActive && root.rowIndex === row.cursorIndex
        foreground: root.foreground

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            root.cursorActive = true
            root.cursorFromMouse = true
            root.rowIndex = row.cursorIndex
          }
          onExited: if (root.cursorFromMouse && root.rowIndex === row.cursorIndex)
            root.cursorActive = false
          onClicked: root.openClient(row.thread)
        }

        RowLayout {
          id: heading
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            text: row.thread.is_group ? "󰡉" : "󰏲"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text {
              Layout.fillWidth: true
              text: row.thread.name || ""
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              text: root.preview(row.thread)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              visible: text !== ""
              text: root.previewTimestamp(row.thread)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            visible: root.threadIsStarred(row.thread)
            text: "★"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Accessible.name: "Starred"
          }
        }
      }

      QuickReply {
        id: inlineReply
        objectName: "quickReply"
        x: Style.space(10)
        width: parent.width - Style.space(20)
        controller: root.controllerFor(row.thread)
        foreground: root.foreground
        urgent: root.urgent
        fontFamily: root.fontFamily
        onLeaveRequested: root.closeReply()
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    width: parent.width
    spacing: Style.space(8)

    Text {
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
