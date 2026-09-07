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
  property string errorText: ""
  property bool cursorActive: false
  property int rowIndex: 0
  property int statusRequestId: 0
  property int threadsRequestId: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string summary: !componentsInstalled ? "Not installed"
    : !configured ? "Setup required"
    : connected ? "Connected" : "Reconnecting"
  readonly property var recentThreads: {
    var unread = []
    for (var index = 0; index < threads.length; ++index) {
      if (threadIsUnread(threads[index])) unread.push(threads[index])
      if (unread.length >= 5) break
    }
    return unread
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
    replyController.selectThread(thread)
    Qt.callLater(function() { quickReply.focusEditor() })
  }

  function closeReply() {
    replyController.back()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
      if (replyController.threadKey !== "") quickReply.focusEditor()
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

  ReplyController {
    id: replyController
    bridge: backendBridge
    threads: root.threads
    connected: root.connected
  }

  Connections {
    target: backendBridge

    function onResponse(method, requestId, result) {
      if (replyController.handleResponse(method, requestId)) {
        root.requestThreads()
        return
      }
      if (method === "status" && requestId === root.statusRequestId) {
        root.statusRequestId = 0
        if (typeof result !== "object" || result === null) {
          root.connected = false
          root.errorText = "BlueFerry returned invalid status data"
          return
        }
        root.backendStatus = result
        root.connected = result.daemon === true && result.map === true
        root.errorText = ""
      } else if (method === "threads" && requestId === root.threadsRequestId) {
        root.threadsRequestId = 0
        root.threads = Array.isArray(result) ? result : []
        root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.recentThreads.length))
      }
    }

    function onFailure(method, requestId, message) {
      replyController.handleFailure(method, requestId, message)
      if (method === "status" || method === "") {
        if (method === "" || requestId === root.statusRequestId)
          root.statusRequestId = 0
        root.connected = false
        if (root.configured) root.errorText = message
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
    focusTarget: replyController.threadKey !== "" ? quickReply : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: replyController.threadKey !== ""
      onMoveRequested: function(_dx, dy) {
        root.cursorActive = true
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
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.configured && replyController.threadKey === ""
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
            visible: root.recentThreads.length > 0 && replyController.threadKey === ""
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "UNREAD"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.recentThreads
              RecentRow {
                required property var modelData
                required property int index
                width: parent.width
                thread: modelData
                cursorIndex: index
              }
            }
          }

          QuickReply {
            id: quickReply
            objectName: "quickReply"
            visible: replyController.threadKey !== ""
            width: parent.width
            controller: replyController
            foreground: root.foreground
            urgent: root.urgent
            fontFamily: root.fontFamily
            onBackRequested: root.closeReply()
            onOpenRequested: thread => root.openClient(thread)
            onActiveFocusChanged: if (activeFocus) focusEditor()
          }

          CursorSurface {
            id: openRow
            visible: replyController.threadKey === ""
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
              onEntered: { root.cursorActive = true; root.rowIndex = root.recentThreads.length }
              onClicked: root.openClient()
            }
          }
        }
      }
    }
  }

  component RecentRow: CursorSurface {
    id: row
    property var thread: null
    property int cursorIndex: 0
    hasCursor: root.cursorActive && root.rowIndex === cursorIndex
    foreground: root.foreground
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.rowIndex = row.cursorIndex }
      onClicked: root.openReply(row.thread)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: row.thread && row.thread.is_group ? "󰡉" : "󰏲"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: content
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: row.thread ? row.thread.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: root.preview(row.thread)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          text: root.previewTimestamp(row.thread)
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
