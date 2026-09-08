"""Exercise the real QML reply controller with an in-memory backend."""

import json
import os
from pathlib import Path

import pytest

# Never inherit a desktop or live BlueFerry/BlueZ bus in these tests.
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/tmp/blueferry-widget-no-bus"
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/tmp/blueferry-widget-no-bus"
os.environ.pop("QT_QPA_PLATFORMTHEME", None)
os.environ.pop("QT_STYLE_OVERRIDE", None)

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def application():
    return QGuiApplication.instance() or QGuiApplication([])


@pytest.fixture
def reply(application):
    engine = QQmlEngine()
    component = QQmlComponent(engine)
    component.setData(b'''import QtQuick
Item {
  id: harness
  property alias reply: controller
  property var calls: []
  property int nextId: 1
  function request(method, args) {
    calls = calls.concat([{method: method, args: args}])
    return nextId++
  }
  ReplyController { id: controller; bridge: harness; connected: true }
}
''', QUrl.fromLocalFile(str(ROOT / "TestHarness.qml")))
    harness = component.create()
    assert harness, "\n".join(error.toString() for error in component.errors())
    engine.globalObject().setProperty("harness", engine.newQObject(harness))
    engine.evaluate("var reply = harness.reply")

    def evaluate(script):
        result = engine.evaluate(script)
        assert not result.isError(), result.toString()
        return result.toVariant()

    evaluate('''var alice = {key:"contact:alice", name:"Alice", reply_ready:true,
        is_group:false, unread:true, messages:[]};
      var bob = {key:"contact:bob", name:"Bob", reply_ready:true,
        is_group:false, unread:true, messages:[]};
      var group = {key:"group:friends", name:"Friends", reply_ready:true,
        is_group:true, confirmation_token:"saved-roster", messages:[]};
      reply.threads = [alice, bob, group]; reply.selectThread(alice);''')
    yield evaluate
    harness.deleteLater()
    application.processEvents()


def test_send_routes_through_checked_thread_api_and_prevents_double_send(reply):
    body = 'hello "there" $(touch /tmp/not-a-command) 🛳'
    reply(f"reply.edit({json.dumps(body)})")
    assert reply("reply.send()") is True
    assert reply("reply.send()") is False
    assert reply("harness.calls") == [{"method": "send_to_thread", "args": {
        "thread_key": "contact:alice", "body": body,
        "confirm_group": False, "expected_group_token": "",
    }}]
    assert reply("reply.text") == body
    assert reply('reply.handleResponse("send_to_thread", 1)') is True
    assert reply("reply.text") == ""
    assert reply("reply.notice") == "Sent"


@pytest.mark.parametrize("setup", [
    'reply.edit("   ")',
    'reply.edit("hello"); reply.connected = false',
    'reply.edit("hello"); reply.threads = []',
    'reply.edit("hello"); reply.threads = [Object.assign({}, alice, {reply_ready:false})]',
])
def test_unavailable_or_empty_replies_never_send(reply, setup):
    reply(setup)
    assert reply("reply.canSend") is False
    assert reply("reply.send()") is False
    assert reply("harness.calls") == []


def test_group_reply_uses_saved_roster_token(reply):
    reply('reply.selectThread(group); reply.edit("hello everyone"); reply.send()')
    assert reply("harness.calls[0].args") == {
        "thread_key": "group:friends", "body": "hello everyone",
        "confirm_group": True, "expected_group_token": "saved-roster",
    }


@pytest.mark.parametrize("change", [
    '{confirmation_token:"new-roster"}',
    '{confirmation_token:""}',
    '{participants_required:true}',
    '{roster_changed:true}',
])
def test_group_change_while_composing_blocks_send_and_preserves_draft(reply, change):
    reply('reply.selectThread(group); reply.edit("hello everyone")')
    reply(f"reply.threads = [Object.assign({{}}, group, {change})]")
    assert reply("reply.send()") is False
    assert reply("reply.text") == "hello everyone"
    assert reply("reply.blockedReason")
    assert reply("harness.calls") == []


def test_drafts_survive_back_navigation_and_history_refresh(reply):
    reply('reply.edit("Alice draft"); reply.back(); reply.selectThread(bob)')
    assert reply("reply.text") == ""
    reply('reply.edit("Bob draft"); reply.selectThread(alice)')
    reply('reply.threads = [Object.assign({}, alice, {unread:false}), bob]')
    assert reply("reply.text") == "Alice draft"
    assert reply("reply.thread.key") == "contact:alice"
    reply("reply.selectThread(bob)")
    assert reply("reply.text") == "Bob draft"


def test_late_success_only_clears_the_sent_threads_draft(reply):
    reply('reply.edit("Alice draft"); reply.send(); reply.selectThread(bob); reply.edit("Bob draft")')
    assert reply('reply.handleResponse("send_to_thread", 999)') is False
    assert reply('reply.handleResponse("threads", 1)') is False
    assert reply("reply.sending") is True
    assert reply('reply.handleResponse("send_to_thread", 1)') is True
    assert reply("reply.text") == "Bob draft"
    assert reply("reply.notice") == ""
    reply("reply.selectThread(alice)")
    assert reply("reply.text") == ""
    assert reply("reply.notice") == "Sent"


def test_failure_belongs_to_original_thread_and_never_automatically_retries(reply):
    reply('reply.edit("Alice draft"); reply.send(); reply.selectThread(bob); reply.edit("Bob draft")')
    assert reply('reply.handleFailure("send_to_thread", 999, "stale error")') is False
    assert reply('reply.handleFailure("send_to_thread", 1, "Phone disconnected")') is True
    assert reply("reply.error") == ""
    assert reply("reply.text") == "Bob draft"
    reply("reply.selectThread(alice); reply.connected = false; reply.connected = true")
    assert reply("reply.text") == "Alice draft"
    assert reply("reply.error") == "Phone disconnected"
    assert reply("harness.calls.length") == 1


def test_bridge_exit_preserves_draft_and_reports_uncertain_delivery(reply):
    reply('reply.edit("hello"); reply.send()')
    assert reply('reply.handleFailure("", 0, "Bridge exited")') is True
    assert reply("reply.text") == "hello"
    assert reply("reply.sending") is False
    assert "before trying again" in reply("reply.error")
    assert reply('reply.handleResponse("send_to_thread", 1)') is False
    assert reply("harness.calls.length") == 1


def test_composing_thread_cannot_be_edited_while_its_send_is_pending(reply):
    reply('reply.edit("original"); reply.send(); reply.edit("replacement")')
    assert reply("reply.text") == "original"
