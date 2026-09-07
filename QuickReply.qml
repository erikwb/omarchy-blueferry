pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

ColumnLayout {
  id: root
  required property ReplyController controller
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  readonly property var conversation: controller.thread || controller.snapshot
  readonly property var messages: conversation && conversation.messages || []
  readonly property var lastMessage: messages.length ? messages[messages.length - 1] : null

  signal backRequested()
  signal openRequested(var thread)

  spacing: Style.space(12)
  Keys.onEscapePressed: root.backRequested()

  function focusEditor() { replyField.forceActiveFocus() }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)

    PanelActionButton {
      id: backButton
      iconText: "←"
      tooltipText: "Back to unread conversations"
      Accessible.name: tooltipText
      foreground: root.foreground
      fontFamily: root.fontFamily
      focusable: true
      onClicked: root.backRequested()
    }

    Text {
      Layout.fillWidth: true
      text: root.conversation ? root.conversation.name : "Reply"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    PanelActionButton {
      id: openButton
      objectName: "openThreadButton"
      iconText: "↗"
      tooltipText: "Open conversation in BlueFerry"
      Accessible.name: tooltipText
      foreground: root.foreground
      fontFamily: root.fontFamily
      focusable: true
      onClicked: root.openRequested(root.conversation)
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.lastMessage !== null
    text: root.lastMessage
      ? (root.lastMessage.outgoing ? "You: " : "") + String(root.lastMessage.body || "") : ""
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
    maximumLineCount: 4
    elide: Text.ElideRight
  }

  Text {
    Layout.fillWidth: true
    visible: text !== ""
    text: root.controller.blockedReason
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)

    TextField {
      id: replyField
      objectName: "replyField"
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      foreground: root.foreground
      font.family: root.fontFamily
      placeholderText: "Write a reply…"
      Accessible.name: "Reply message"
      text: root.controller.text
      readOnly: root.controller.sendingThisThread
      selectByMouse: true
      onTextEdited: root.controller.edit(text)
      onAccepted: root.controller.send()
      Keys.onEscapePressed: root.backRequested()
      KeyNavigation.tab: sendButton.enabled ? sendButton : openButton
      KeyNavigation.backtab: backButton
    }

    Button {
      id: sendButton
      objectName: "sendButton"
      text: root.controller.sendingThisThread ? "Sending…" : "Send"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      focusable: true
      enabled: root.controller.canSend
      opacity: enabled ? 1 : 0.5
      onClicked: root.controller.send()
      KeyNavigation.tab: openButton
      KeyNavigation.backtab: replyField
    }
  }

  Text {
    Layout.fillWidth: true
    visible: text !== ""
    text: root.controller.error || root.controller.notice
    textFormat: Text.PlainText
    color: root.controller.error ? root.urgent : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }
}
