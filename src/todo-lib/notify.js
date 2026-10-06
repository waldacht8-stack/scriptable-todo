// todo-lib/notify.js
// ローカル通知の予約。毎回「このアプリの予約を全部消して作り直す」方式で、状態ずれを起こさない。

// model は TODO.js から渡す（importModule の相対パス解決に依存しないため）

const PREFIX = 'todo-'

function openURL() {
  return URLScheme.forRunningScript()
}

async function reschedule(data, now, model) {
  const pending = await Notification.allPending()
  const ids = pending.map(n => n.identifier).filter(id => id && id.indexOf(PREFIX) === 0)
  if (ids.length) await Notification.removePending(ids)
  const plans = model.planNotifications(data, now)
  for (const p of plans) {
    const n = new Notification()
    n.identifier = p.id
    n.threadIdentifier = 'todo'
    n.title = p.title
    n.body = p.body
    n.openURL = openURL()
    n.setTriggerDate(new Date(p.at))
    await n.schedule()
  }
  return plans.length
}

// 自動処理のエラーをすぐ通知する（同じ状態で連発しないよう6時間に1回まで）
async function error(data, message, now) {
  const last = data.meta.lastErrorAt ? new Date(data.meta.lastErrorAt) : null
  if (last && now - last < 6 * 3600 * 1000) return false
  const n = new Notification()
  n.identifier = PREFIX + 'error'
  n.threadIdentifier = 'todo'
  n.title = '同期エラー'
  n.body = message
  n.openURL = openURL()
  await n.schedule()
  data.meta.lastErrorAt = now.toISOString()
  return true
}

module.exports = { reschedule, error }
