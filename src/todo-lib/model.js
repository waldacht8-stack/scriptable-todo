// todo-lib/model.js
// TODOの分類・表示用の整形・カレンダー取り込み・通知計画などの純粋関数。
// Scriptable の API に依存しないので、WebView 側にも関数ソースをそのまま埋め込んで共用する。
// （埋め込みのため、各関数はこのファイル内の他の関数以外を参照しないこと）

function startOfDay(d) {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  return x
}

function addDays(d, n) {
  const x = new Date(d)
  x.setDate(x.getDate() + n)
  return x
}

function pad2(n) {
  return (n < 10 ? '0' : '') + n
}

function fmtTime(d) {
  return pad2(d.getHours()) + ':' + pad2(d.getMinutes())
}

function fmtDate(d) {
  const w = ['日', '月', '火', '水', '木', '金', '土'][d.getDay()]
  return (d.getMonth() + 1) + '月' + d.getDate() + '日（' + w + '）'
}

// 一覧やウィジェットに出す期限ラベル（例: "14:00" / "昨日 17:00" / "10/12（月）" / "期限なし"）
function fmtDue(t, now) {
  if (!t.due) return '期限なし'
  const d = new Date(t.due)
  const diff = Math.round((startOfDay(d) - startOfDay(now)) / 86400000)
  const w = ['日', '月', '火', '水', '木', '金', '土'][d.getDay()]
  let day
  if (diff === 0) day = '今日'
  else if (diff === -1) day = '昨日'
  else if (diff === 1) day = '明日'
  else day = (d.getMonth() + 1) + '/' + d.getDate() + '（' + w + '）'
  if (t.allDay) return diff === 0 ? '終日' : day
  return diff === 0 ? fmtTime(d) : day + ' ' + fmtTime(d)
}

function compareDue(a, b) {
  const x = a.due ? new Date(a.due).getTime() : Infinity
  const y = b.due ? new Date(b.due).getTime() : Infinity
  if (x !== y) return x < y ? -1 : 1
  const ca = a.createdAt || ''
  const cb = b.createdAt || ''
  return ca < cb ? -1 : ca > cb ? 1 : 0
}

// 一覧・ウィジェットの並び：重要マーク付きを先頭に固定、その中は期限が近い順
function compareTodo(a, b) {
  if (!!a.important !== !!b.important) return a.important ? -1 : 1
  return compareDue(a, b)
}

// 期限切れ / 今日 / 今後 / 今日完了 に振り分ける。期限なしのTODOは「今日」に置く。
function categorize(todos, now) {
  const today = startOfDay(now)
  const tomorrow = addDays(today, 1)
  const g = { overdue: [], today: [], upcoming: [], doneToday: [] }
  for (const t of todos) {
    if (t.done) {
      if (t.doneAt && new Date(t.doneAt) >= today) g.doneToday.push(t)
      continue
    }
    if (!t.due) {
      g.today.push(t)
      continue
    }
    const d = new Date(t.due)
    const overdue = t.allDay ? d < today : d < now
    if (overdue) g.overdue.push(t)
    else if (d < tomorrow) g.today.push(t)
    else g.upcoming.push(t)
  }
  g.overdue.sort(compareTodo)
  g.today.sort(compareTodo)
  g.upcoming.sort(compareTodo)
  g.doneToday.sort((a, b) => (a.doneAt < b.doneAt ? 1 : -1))
  const remaining = g.overdue.length + g.today.length
  g.stats = { remaining: remaining, done: g.doneToday.length, total: remaining + g.doneToday.length }
  return g
}

// ウィジェット・ロック画面に出す「次のTODO」
function nextItem(g, now) {
  const upcomingToday = g.today.filter(t => t.due && !t.allDay && new Date(t.due) >= now)
  return upcomingToday[0] || g.today[0] || g.overdue[0] || null
}

function isOverdue(t, now) {
  if (t.done || !t.due) return false
  const d = new Date(t.due)
  return t.allDay ? d < startOfDay(now) : d < now
}

// ウィジェット用：未完了を期限が近い順（期限切れ → 近い順 → 期限なし）に並べる。
// next は「次の期限まで」のカウントダウン対象（時刻つきで、まだ来ていない一番近いもの）
function byDeadline(todos, now) {
  const items = todos.filter(t => !t.done).sort(compareTodo)
  return {
    items: items,
    overdue: items.filter(t => isOverdue(t, now)).length,
    next: items.find(t => t.due && !t.allDay && new Date(t.due) > now) || null,
  }
}

function newId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
}

// カレンダーの予定（{key,title,due,allDay,calendarTitle}）を TODO に反映する。
// - 新しい予定は追加、未完了TODOはタイトル・日時の変更を反映
// - 取り込み範囲内で予定が消えた未完了TODOは削除
// - アプリで削除した予定（dismissed）は再取り込みしない
function mergeEvents(data, events, rangeStart, rangeEnd, now) {
  const byKey = {}
  for (const t of data.todos) if (t.source === 'calendar') byKey[t.eventKey] = t
  const seen = {}
  for (const ev of events) seen[ev.key] = true
  const result = { added: 0, updated: 0, removed: 0 }
  const stamp = now.toISOString()
  for (const ev of events) {
    if (data.dismissed[ev.key]) continue
    let t = byKey[ev.key]
    if (!t) {
      // アプリから登録した予定は、保存直後の識別子が同期で見える識別子と異なることがあるので、
      // 「どの予定にも対応していないカレンダー由来TODO」をタイトルと日時で照合して付け替える
      t = data.todos.find(x => x.source === 'calendar' && !seen[x.eventKey] && x.title === ev.title && x.due === ev.due)
      if (t) {
        t.eventKey = ev.key
        byKey[ev.key] = t
      }
    }
    if (!t) {
      data.todos.push({
        id: newId(), title: ev.title, due: ev.due, allDay: ev.allDay, note: '',
        done: false, doneAt: null, source: 'calendar', eventKey: ev.key,
        calendarTitle: ev.calendarTitle, createdAt: stamp, updatedAt: stamp,
      })
      result.added++
    } else if (!t.done && (t.title !== ev.title || t.due !== ev.due || t.allDay !== ev.allDay)) {
      t.title = ev.title
      t.due = ev.due
      t.allDay = ev.allDay
      t.calendarTitle = ev.calendarTitle
      t.updatedAt = stamp
      result.updated++
    }
  }
  data.todos = data.todos.filter(t => {
    if (t.source !== 'calendar' || t.done || !t.due) return true
    const d = new Date(t.due)
    if (d < rangeStart || d >= rangeEnd || seen[t.eventKey]) return true
    result.removed++
    return false
  })
  for (const k of Object.keys(data.dismissed)) {
    if (new Date(data.dismissed[k]) < rangeStart) delete data.dismissed[k]
  }
  return result
}

// 完了から30日以上たったTODOを削除する
function pruneDone(data, now) {
  const limit = addDays(now, -30)
  data.todos = data.todos.filter(t => !(t.done && t.doneAt && new Date(t.doneAt) < limit))
}

// 予約する通知の一覧を作る（朝の一覧・夜の残り 各3日分 + 期限前リマインド + スヌーズ）。iOSの上限64件に収める。
// morningHour / eveningHour / remindMinutes が null の通知は送らない
function planNotifications(data, now) {
  const s = data.settings
  const plans = []
  for (let i = 0; i < 3 && s.morningHour != null; i++) {
    const at = addDays(startOfDay(now), i)
    at.setHours(s.morningHour, s.morningMinute || 0, 0, 0)
    if (at <= now) continue
    const g = categorize(data.todos, at)
    if (g.stats.remaining === 0) continue
    // 本文は1件1行（通知を広げると一覧として読める）
    const lines = []
    if (g.overdue.length) lines.push('⚠︎ 期限切れ ' + g.overdue.length + '件')
    const shown = g.today.slice(0, 3)
    for (const t of shown) lines.push('・' + (t.due && !t.allDay ? fmtTime(new Date(t.due)) + ' ' : '') + t.title)
    const rest = g.today.length - shown.length
    if (rest > 0) lines.push('ほか ' + rest + '件')
    plans.push({
      id: 'todo-morning-' + i,
      at: at.toISOString(),
      title: '今日のTODO ' + g.stats.remaining + '件',
      body: lines.join('\n'),
    })
  }
  for (let i = 0; i < 3 && s.eveningHour != null; i++) {
    const at = addDays(startOfDay(now), i)
    at.setHours(s.eveningHour, s.eveningMinute || 0, 0, 0)
    if (at <= now) continue
    const g = categorize(data.todos, at)
    if (g.stats.remaining === 0) continue
    const items = g.overdue.concat(g.today)
    const lines = items.slice(0, 3).map(t => '・' + t.title)
    if (items.length > 3) lines.push('ほか ' + (items.length - 3) + '件')
    plans.push({
      id: 'todo-evening-' + i,
      at: at.toISOString(),
      title: '今日の残り ' + g.stats.remaining + '件',
      body: lines.join('\n'),
    })
  }
  // スヌーズ（「10分後にもう一度」）
  for (const t of data.todos) {
    if (t.done || !t.snoozeUntil || new Date(t.snoozeUntil) <= now) continue
    plans.push({
      id: 'todo-snooze-' + t.id,
      todoId: t.id,
      at: t.snoozeUntil,
      title: 'もう一度：' + t.title,
      body: (t.due ? '期限 ' + fmtDue(t, new Date(t.snoozeUntil)) + '\n' : '') + ACTION_HINT,
    })
  }
  const room = 64 - plans.length - 2
  const reminders = s.remindMinutes == null ? [] : data.todos
    .filter(t => !t.done && t.due && !t.allDay)
    .map(t => ({ t: t, at: new Date(new Date(t.due).getTime() - s.remindMinutes * 60000) }))
    .filter(x => x.at > now)
    .sort((a, b) => a.at - b.at)
    .slice(0, Math.max(0, room))
  for (const x of reminders) {
    plans.push({
      id: 'todo-remind-' + x.t.id,
      todoId: x.t.id,
      at: x.at.toISOString(),
      title: (s.remindMinutes ? 'あと' + durationLabel(s.remindMinutes) + '：' : '期限です：') + x.t.title,
      body: fmtTime(new Date(x.t.due)) + (x.t.source === 'calendar' ? ' 開始' : ' 期限') + '\n' + ACTION_HINT,
    })
  }
  return plans
}

const ACTION_HINT = '長押しで「完了」「10分後に再通知」'

// 30 → "30分" / 60 → "1時間" / 90 → "1時間30分"
function durationLabel(min) {
  const h = Math.floor(min / 60)
  const m = min % 60
  return (h ? h + '時間' : '') + (m || !h ? m + '分' : '')
}

function repeatLabel(r) {
  return ({ daily: '毎日', weekdays: '平日', weekly: '毎週', monthly: '毎月' })[r] || ''
}

// 繰り返しTODOの次の期限。今日より前にならないところまで進める（毎月は元の「日」を保つ、月末は丸める）
function nextOccurrence(t, now) {
  if (!t.repeat || !t.due) return null
  const anchor = t.repeatDay || new Date(t.due).getDate()
  const step = d => {
    const x = new Date(d)
    if (t.repeat === 'daily') x.setDate(x.getDate() + 1)
    else if (t.repeat === 'weekdays') {
      do { x.setDate(x.getDate() + 1) } while (x.getDay() === 0 || x.getDay() === 6)
    } else if (t.repeat === 'weekly') x.setDate(x.getDate() + 7)
    else if (t.repeat === 'monthly') {
      x.setDate(1)
      x.setMonth(x.getMonth() + 1)
      x.setDate(Math.min(anchor, new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate()))
    } else return null
    return x
  }
  let d = step(new Date(t.due))
  const today = startOfDay(now)
  for (let i = 0; d && d < today && i < 1000; i++) d = step(d)
  return d
}

// 完了にする。繰り返しなら次の回を todos に追加して返す（取り消し用に spawnedId を残す）
function completeTodo(todos, t, now) {
  const stamp = now.toISOString()
  t.done = true
  t.doneAt = stamp
  t.updatedAt = stamp
  delete t.snoozeUntil
  const due = t.source === 'calendar' ? null : nextOccurrence(t, now)
  if (!due) return null
  const next = Object.assign({}, t, {
    id: newId(), due: due.toISOString(), done: false, doneAt: null, createdAt: stamp, updatedAt: stamp,
    repeatDay: t.repeatDay || new Date(t.due).getDate(),
  })
  delete next.spawnedId
  t.spawnedId = next.id
  todos.push(next)
  return next
}

// 完了を取り消す。繰り返しで作られた次の回がまだ未完了なら消す
function uncompleteTodo(todos, t, now) {
  t.done = false
  t.doneAt = null
  t.updatedAt = now.toISOString()
  if (t.spawnedId) {
    const i = todos.findIndex(x => x.id === t.spawnedId && !x.done)
    if (i >= 0) todos.splice(i, 1)
    delete t.spawnedId
  }
}

module.exports = {
  startOfDay, addDays, pad2, fmtTime, fmtDate, fmtDue, compareDue, compareTodo, categorize, nextItem,
  newId, mergeEvents, pruneDone, planNotifications, isOverdue, byDeadline,
  repeatLabel, durationLabel, nextOccurrence, completeTodo, uncompleteTodo,
}
