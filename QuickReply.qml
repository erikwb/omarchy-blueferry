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
  readonly property Item focusTarget: replyField
  property Item openButton: null

  signal leaveRequested()

  spacing: Style.space(6)
  Keys.onEscapePressed: root.leaveRequested()

  function focusEditor() { replyField.forceActiveFocus() }

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
      Keys.onEscapePressed: root.leaveRequested()
      KeyNavigation.tab: sendButton.enabled ? sendButton : root.openButton
      KeyNavigation.backtab: root.openButton
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
      KeyNavigation.tab: root.openButton
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
