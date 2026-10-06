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

module.exports = { syncCalendar }
