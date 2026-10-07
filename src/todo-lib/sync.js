// todo-lib/sync.js
// iOSカレンダーの予定を読み、TODOへ反映する。model は TODO.js から渡す。

async function readEvents(settings, rangeStart, rangeEnd) {
  const calendars = (await Calendar.forEvents()).filter(c => settings.excludeCalendars.indexOf(c.title) < 0)
  // between() はカレンダー配列が空だと「全カレンダー」扱いになるので、空なら読まない
  if (!calendars.length) return []
  const events = await CalendarEvent.between(rangeStart, rangeEnd, calendars)
  return events
    .filter(ev => ev.startDate >= rangeStart) // 前日から続く複数日の予定は対象外
    .map(ev => ({
      key: ev.identifier + '@' + ev.startDate.toISOString(), // 繰り返し予定は identifier が共通なので開始日時で区別
      title: ev.title || '(無題の予定)',
      due: ev.startDate.toISOString(),
      allDay: !!ev.isAllDay,
      calendarTitle: ev.calendar ? ev.calendar.title : '',
    }))
}

async function syncCalendar(data, now, model) {
  const rangeStart = model.startOfDay(now)
  const rangeEnd = model.addDays(rangeStart, data.settings.lookaheadDays)
  const events = await readEvents(data.settings, rangeStart, rangeEnd)
  const result = model.mergeEvents(data, events, rangeStart, rangeEnd, now)
  model.pruneDone(data, now)
  data.meta.lastSync = now.toISOString()
  return result
}

// 予定を書き込めるカレンダー名（既定のカレンダーを先頭に）。画面の「登録先」選択肢に使う
async function writableCalendars(settings) {
  const all = (await Calendar.forEvents())
    .filter(c => c.allowsContentModifications && settings.excludeCalendars.indexOf(c.title) < 0)
  let def = null
  try { def = await Calendar.defaultForEvents() } catch (e) { /* 既定が取れなくても一覧は出す */ }
  const titles = all.map(c => c.title)
  const i = def ? titles.indexOf(def.title) : -1
  if (i > 0) {
    titles.splice(i, 1)
    titles.unshift(def.title)
  }
  return titles
}

// 画面で「カレンダーにも登録」した TODO（pendingEvent）を iOS カレンダーに予定として作り、
// カレンダー由来の TODO に切り替える。画面は保存のたびに全 TODO を送ってくる（pendingEvent が残ったまま）ので、
// 作成済みかどうかは meta.eventLinks（TODO id → 予定）で判定して二重に作らない。
// 戻り値: { created: [{ title, calendarTitle }], failed: [{ title, message }] }（失敗分は pendingEvent のまま残り再試行される）
async function createPendingEvents(data) {
  const links = data.meta.eventLinks = data.meta.eventLinks || {}
  const result = { created: [], failed: [] }
  for (const t of data.todos) {
    if (!t.pendingEvent) continue
    let link = links[t.id]
    if (!link) {
      if (!t.due) { delete t.pendingEvent; continue }
      try {
        link = await saveEvent(t)
      } catch (e) {
        result.failed.push({ title: t.title, message: e && e.message ? e.message : String(e) })
        continue
      }
      links[t.id] = link
      result.created.push({ title: t.title, calendarTitle: link.calendarTitle })
    }
    t.source = 'calendar'
    t.eventKey = link.eventKey
    t.calendarTitle = link.calendarTitle
    delete t.pendingEvent
  }
  // 画面で削除された TODO の予定は、次の同期で取り込み直さない
  const ids = {}
  for (const t of data.todos) ids[t.id] = true
  for (const id of Object.keys(links)) {
    if (ids[id]) continue
    data.dismissed[links[id].eventKey] = links[id].due
    delete links[id]
  }
  return result
}

async function saveEvent(t) {
  const start = new Date(t.due)
  const ev = new CalendarEvent()
  ev.title = t.title
  ev.startDate = start
  ev.endDate = t.allDay ? start : new Date(start.getTime() + 3600 * 1000)
  ev.isAllDay = !!t.allDay
  if (t.note) ev.notes = t.note
  // calendar はドキュメント上「読み取り専用」なので、代入できなくても既定のカレンダーに保存する
  const want = typeof t.pendingEvent === 'string' ? t.pendingEvent : null
  if (want) {
    try {
      const cal = (await Calendar.forEvents()).find(c => c.title === want && c.allowsContentModifications)
      if (cal) ev.calendar = cal
    } catch (e) {
      console.warn('登録先カレンダーを指定できませんでした: ' + e)
    }
  }
  await ev.save()
  const calendarTitle = ev.calendar ? ev.calendar.title : 'カレンダー'
  return { eventKey: ev.identifier + '@' + start.toISOString(), calendarTitle: calendarTitle, due: t.due }
}

module.exports = { syncCalendar, writableCalendars, createPendingEvents }
