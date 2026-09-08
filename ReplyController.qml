import QtQuick

// Keep drafts and in-flight sends outside the popup's visual lifetime.
QtObject {
  id: root

  property var bridge: null
  property var threads: []
  property bool connected: false
  property string threadKey: ""
  property var snapshot: null
  property string groupToken: ""
  property var drafts: ({})
  property int sendRequestId: 0
  property string sendingKey: ""
  property string sendingBody: ""

  readonly property var thread: {
    for (var index = 0; index < threads.length; ++index) {
      if (threads[index].key === threadKey) return threads[index]
    }
    return null
  }
  readonly property var state: drafts["$" + threadKey] || ({})
  readonly property string text: state.text || ""
  readonly property string error: state.error || ""
  readonly property string notice: state.notice || ""
  readonly property bool sending: sendRequestId !== 0
  readonly property bool sendingThisThread: sending && sendingKey === threadKey
  readonly property string blockedReason: {
    if (threadKey === "") return ""
    if (!thread) return "This conversation is unavailable. Open it in BlueFerry to continue."
    if (thread.participants_required || thread.roster_changed)
      return "Review this group's members in BlueFerry before replying."
    if (thread.reply_ready !== true)
      return "Open this conversation in BlueFerry to set up replies."
    if (thread.is_group && (!groupToken || thread.confirmation_token !== groupToken))
      return "Group members changed. Open this conversation in BlueFerry before replying."
    if (!connected) return "Waiting for the iPhone to reconnect…"
    return ""
  }
  readonly property bool canSend: threadKey !== "" && blockedReason === ""
    && text.trim() !== "" && !sending

  function updateState(key, values) {
    var updated = Object.assign({}, drafts)
    updated["$" + key] = Object.assign({}, updated["$" + key] || {}, values)
    drafts = updated
  }

  function selectThread(value) {
    if (!value || !value.key) return
    snapshot = value
    groupToken = value.is_group ? String(value.confirmation_token || "") : ""
    threadKey = String(value.key)
  }

  function back() {
    threadKey = ""
    snapshot = null
    groupToken = ""
  }

  function edit(value) {
    if (threadKey === "" || sendingThisThread) return
    updateState(threadKey, {text: value, notice: ""})
  }

  function send() {
    if (!canSend || !bridge) return false
    sendingKey = threadKey
    sendingBody = text
    updateState(sendingKey, {error: "", notice: ""})
    sendRequestId = bridge.request("send_to_thread", {
      thread_key: sendingKey,
      body: sendingBody,
      confirm_group: thread.is_group === true,
      expected_group_token: groupToken
    })
    return true
  }

  function handleResponse(method, requestId) {
    if (method !== "send_to_thread" || requestId !== sendRequestId || !sending)
      return false
    var state = drafts["$" + sendingKey] || {}
    updateState(sendingKey, {
      text: state.text === sendingBody ? "" : state.text,
      error: "",
      notice: "Sent"
    })
    sendRequestId = 0
    sendingKey = ""
    sendingBody = ""
    return true
  }

  function handleFailure(method, requestId, message) {
    if (!sending) return false
    if (method !== "" && (method !== "send_to_thread" || requestId !== sendRequestId))
      return false
    updateState(sendingKey, {
      error: method === ""
        ? "Connection lost while sending. Check this conversation in BlueFerry before trying again."
        : message || "Could not send your reply.",
      notice: ""
    })
    sendRequestId = 0
    sendingKey = ""
    sendingBody = ""
    return true
  }
}
