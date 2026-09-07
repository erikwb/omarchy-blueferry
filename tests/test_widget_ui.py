"""Run the Omarchy controls in a desktop-free Quickshell sandbox."""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
OMARCHY = Path("/usr/share/omarchy/shell")


def test_reply_keyboard_and_draft_bindings(tmp_path):
    if not all(shutil.which(tool) for tool in ("bwrap", "quickshell")) or not OMARCHY.is_dir():
        pytest.skip("requires Omarchy, Quickshell, and bubblewrap")

    (tmp_path / "artifacts").mkdir()
    for directory in ("Commons", "Ui"):
        shutil.copytree(OMARCHY / directory, tmp_path / directory)
    # The offscreen platform has no layer-shell surfaces. Replace only that
    # window wrapper; the panel, input, buttons, and key dispatcher stay real.
    (tmp_path / "Ui/KeyboardPanel.qml").write_text('''import QtQuick
Item {
  required property Item anchorItem
  required property QtObject bar
  property var owner
  property bool open: false
  property Item focusTarget
  property int contentWidth: 360
  property int contentHeight: 500
  width: contentWidth
  height: contentHeight
  visible: open
  function fittedContentWidth(value) { return value }
  function fittedContentHeight(value, cap) { return Math.min(value, cap) }
  onOpenChanged: if (open && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
}
''')
    for name in ("Panel.qml", "ReplyController.qml", "QuickReply.qml"):
        shutil.copyfile(ROOT / name, tmp_path / name)
    (tmp_path / "blueferry-cli").write_text('#!/bin/sh\nprintf \'{"configured":true}\\n\'\n')
    (tmp_path / "blueferry-cli").chmod(0o755)
    (tmp_path / "BackendBridge.qml").write_text('''import QtQuick
Item {
  id: root
  property bool active: true
  property int nextId: 1
  signal response(string method, int requestId, var result)
  signal failure(string method, int requestId, string message)
  signal eventReceived(string name, var data)
  function request(method, args) {
    var id = nextId++
    Qt.callLater(function() {
      if (method === "status") root.response(method, id, {daemon:true, map:true, pbap:true})
      else if (method === "threads") root.response(method, id,
        [{key:"alice", name:"Alice", reply_ready:true, is_group:false, unread:true, messages:[]}])
      else if (method === "send_to_thread") root.response(method, id, "fake-transfer")
    })
    return id
  }
}
''')
    (tmp_path / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Ui
import "." as Plugin

ShellRoot {
  id: root
  property var calls: []
  property int nextId: 1
  property int panelActivations: 0
  property int panelMoves: 0
  property int backCount: 0
  property var alice: ({key:"alice", name:"Alice", is_group:false, reply_ready:true,
    messages:[{body:"Ready when you are", outgoing:false}]})
  property var bob: ({key:"bob", name:"Bob", is_group:false, reply_ready:true, messages:[]})
  function request(method, args) {
    calls = calls.concat([{method:method, args:args}]); return nextId++
  }
  ReplyController {
    id: controller
    bridge: root
    connected: true
    threads: [root.alice, root.bob]
  }
  Window {
    id: window
    width: 360; height: 280; visible: true; color: "#101315"
    Plugin.Panel { id: widget }
    PanelKeyCatcher {
      anchors.fill: parent
      blocked: controller.threadKey !== ""
      onActivateRequested: root.panelActivations++
      onMoveRequested: root.panelMoves++
      QuickReply {
        id: reply
        width: parent.width - 24
        x: 12; y: 12
        controller: controller
        onBackRequested: { root.backCount++; controller.back() }
      }
      TestCase {
        name: "QuickReply"
        when: true
        onCompletedChanged: if (completed)
          console.log("WIDGET_TEST_RESULTS", qtest_results.passCount, qtest_results.failCount)
        function init() {
          root.calls = []; root.panelActivations = 0; root.panelMoves = 0
          controller.sendRequestId = 0; controller.drafts = {}
          controller.selectThread(root.alice)
          window.requestActivate()
          reply.focusEditor()
          wait(100)
        }
        function test_enter_sends_typed_text_without_panel_shortcuts() {
          keyClick(Qt.Key_J); keyClick(Qt.Key_K); keyClick(Qt.Key_L)
          keyClick(Qt.Key_Space); keyClick(Qt.Key_H)
          compare(controller.text, "jkl h")
          keyClick(Qt.Key_Return)
          compare(root.calls.length, 1)
          compare(root.calls[0].args.body, "jkl h")
          compare(root.calls[0].args.thread_key, "alice")
          compare(root.panelActivations, 0)
          compare(root.panelMoves, 0)
          controller.handleResponse("send_to_thread", controller.sendRequestId)
          compare(findChild(reply, "replyField").text, "")
        }
        function test_tab_send_button_and_space_send_once() {
          keyClick(Qt.Key_H)
          keyClick(Qt.Key_Tab)
          verify(findChild(reply, "sendButton").activeFocus)
          keyClick(Qt.Key_Space)
          compare(root.calls.length, 1)
          keyClick(Qt.Key_Return)
          compare(root.calls.length, 1)
          compare(root.panelActivations, 0)
        }
        function test_escape_keeps_the_draft() {
          keyClick(Qt.Key_H)
          var before = root.backCount
          keyClick(Qt.Key_Escape)
          compare(root.backCount, before + 1)
          compare(controller.threadKey, "")
          controller.selectThread(root.alice)
          compare(findChild(reply, "replyField").text, "h")
        }
        function test_switching_threads_restores_each_input() {
          keyClick(Qt.Key_A)
          controller.selectThread(root.bob)
          compare(findChild(reply, "replyField").text, "")
          keyClick(Qt.Key_B)
          controller.selectThread(root.alice)
          compare(findChild(reply, "replyField").text, "a")
          controller.selectThread(root.bob)
          compare(findChild(reply, "replyField").text, "b")
        }
        function test_disconnected_enter_retains_draft() {
          keyClick(Qt.Key_H)
          controller.connected = false
          keyClick(Qt.Key_Return)
          compare(root.calls.length, 0)
          compare(findChild(reply, "replyField").text, "h")
          controller.connected = true
        }
        function test_panel_dispatches_reply_and_handles_success() {
          tryCompare(widget, "connected", true)
          reply.visible = false
          widget.open()
          wait(100)
          keyClick(Qt.Key_Return)
          var inlineReply = findChild(widget, "quickReply")
          verify(inlineReply !== null)
          compare(inlineReply.controller.threadKey, "alice")
          var field = findChild(inlineReply, "replyField")
          tryCompare(field, "activeFocus", true)
          keyClick(Qt.Key_H)
          compare(inlineReply.controller.text, "h")
          keyClick(Qt.Key_Return)
          tryCompare(inlineReply.controller, "notice", "Sent")
          compare(inlineReply.controller.text, "")
          inlineReply.controller.edit("See you soon!")
          widget.close()
          widget.open()
          tryCompare(field, "activeFocus", true)
          compare(field.text, "See you soon!")
          wait(100)
          grabImage(window.contentItem).save("/artifacts/widget.png")
          keyClick(Qt.Key_Escape)
          compare(inlineReply.controller.threadKey, "")
          widget.close()
          reply.visible = true
        }
        function test_layout_keeps_input_and_send_button_inside_panel() {
          var field = findChild(reply, "replyField")
          var button = findChild(reply, "sendButton")
          verify(field.width > 150)
          verify(field.height >= 20)
          verify(reply.height >= reply.implicitHeight)
          verify(button.mapToItem(reply, button.width, 0).x <= reply.width)
          verify(field.mapToItem(reply, 0, field.height).y <= reply.height)
        }
      }
    }
  }
}
''')
    # Only system libraries, fonts, and the fake test config are visible. No
    # home directory, desktop sockets, real bridge, or network is reachable.
    command = [
        "bwrap", "--unshare-all", "--die-with-parent",
        "--ro-bind", "/usr", "/usr", "--ro-bind", "/etc", "/etc",
        "--symlink", "usr/bin", "/bin", "--symlink", "usr/lib", "/lib",
        "--symlink", "usr/lib", "/lib64", "--proc", "/proc", "--dev", "/dev",
        "--tmpfs", "/tmp", "--dir", "/run", "--dir", "/home/test",
        "--ro-bind", str(tmp_path), "/config",
        "--bind", str(tmp_path / "artifacts"), "/artifacts",
        "--ro-bind", str(tmp_path / "blueferry-cli"), "/usr/bin/blueferry",
        "--setenv", "HOME", "/home/test",
        "--setenv", "XDG_RUNTIME_DIR", "/run",
        "--setenv", "XDG_CONFIG_HOME", "/home/test/.config",
        "--setenv", "XDG_STATE_HOME", "/home/test/.local/state",
        "--setenv", "XDG_CACHE_HOME", "/home/test/.cache",
        "--setenv", "DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/no-bus",
        "--setenv", "DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/run/no-bus",
        "--setenv", "QT_QPA_PLATFORM", "offscreen",
        "--setenv", "QT_QUICK_BACKEND", "software",
        "--unsetenv", "QT_QPA_PLATFORMTHEME", "--unsetenv", "QT_STYLE_OVERRIDE",
        "--unsetenv", "WAYLAND_DISPLAY", "--unsetenv", "DISPLAY",
        "--unsetenv", "HYPRLAND_INSTANCE_SIGNATURE",
        "--chdir", "/config", "quickshell", "--path", "/config/shell.qml",
    ]
    result = subprocess.run(command, text=True, capture_output=True, timeout=30, check=False)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "WIDGET_TEST_RESULTS 8 0" in output, output
    assert "FAIL!" not in output, output
    assert "ReferenceError" not in output, output
    assert "TypeError" not in output, output
