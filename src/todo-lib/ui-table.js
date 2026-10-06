// todo-lib/ui-table.js
// 予備のアプリ画面（案1デザイン）。WebView を使わず、Scriptable 標準の UITable で一覧を表示する。
// present(data, ctx) は ui.js と同じ呼び出し方：ctx = { model, error, onMessage(msg) }

const COLORS = {
  accent: Color.dynamic(new Color('#1D4ED8'), new Color('#6EA0FF')),
  overdue: Color.dynamic(new Color('#C2410C'), new Color('#FB923C')),
  overdueBg: Color.dynamic(new Color('#FDEEE6'), new Color('#3A2214')),
  sub: Color.dynamic(new Color('#5A6270'), new Color('#9AA3AF')),
  text: Color.dynamic(new Color('#15181D'), new Color('#F2F4F7')),
  muted: Color.dynamic(new Color('#8A919C'), new Color('#6B7280')),
}

// 行を組み立てる。操作は actions（toggle / open / add / toggleDone）に渡す
function buildRows(table, state, model, error, actions) {
  const now = new Date()
  const g = model.categorize(state.todos, now)

  // ヘッダー
  const head = new UITableRow()
  head.height = 96
  const left = UITableCell.text(model.fmtDate(now), '今日 残り' + g.stats.remaining + '件')
  left.titleFont = Font.semiboldSystemFont(15)
  left.titleColor = COLORS.sub
  left.subtitleFont = Font.boldSystemFont(26)
  left.subtitleColor = COLORS.accent
  left.widthWeight = 60
  head.addCell(left)
  const right = UITableCell.text(g.stats.done + ' / ' + g.stats.total + ' 件 完了')
  right.titleFont = Font.systemFont(13)
  right.titleColor = COLORS.sub
  right.rightAligned()
  right.widthWeight = 40
  head.addCell(right)
  table.addRow(head)

  if (error) {
    const er = new UITableRow()
    er.height = 88
    er.backgroundColor = COLORS.overdueBg
    const c = UITableCell.text(error)
    c.titleFont = Font.semiboldSystemFont(13)
    c.titleColor = COLORS.overdue
    er.addCell(c)
    table.addRow(er)
  }

  function sectionRow(name, count, color) {
    const r = new UITableRow()
    r.isHeader = true
    r.height = 40
    const c = UITableCell.text('● ' + name + '  ' + count)
    c.titleFont = Font.boldSystemFont(15)
    c.titleColor = color
    r.addCell(c)
    table.addRow(r)
  }

  function itemRow(t, kind) {
    const r = new UITableRow()
    r.height = kind === 'small' || kind === 'done' ? 56 : 64
    r.cellSpacing = 8
    r.dismissOnSelect = false
    const color = kind === 'overdue' ? COLORS.overdue : kind === 'today' ? COLORS.accent : COLORS.muted
    const check = UITableCell.button(t.done ? '●' : '○')
    check.titleFont = Font.systemFont(26)
    check.titleColor = t.done ? COLORS.accent : color
    check.widthWeight = 12
    check.centerAligned()
    check.dismissOnTap = false
    check.onTap = () => actions.toggle(t.id)
    r.addCell(check)
    let meta = model.fmtDue(t, now)
    if (t.source === 'calendar') meta += '　カレンダー'
    const body = UITableCell.text(t.title, meta)
    body.titleFont = kind === 'small' || kind === 'done' ? Font.systemFont(16) : Font.boldSystemFont(17)
    body.titleColor = t.done ? COLORS.sub : COLORS.text
    body.subtitleFont = t.due && (kind === 'overdue' || kind === 'today') ? Font.boldSystemFont(13) : Font.systemFont(13)
    body.subtitleColor = t.due && (kind === 'overdue' || kind === 'today') ? color : COLORS.sub
    body.widthWeight = 88
    r.addCell(body)
    r.onSelect = () => actions.open(t.id)
    table.addRow(r)
  }

  function emptyRow(text) {
    const r = new UITableRow()
    r.height = 52
    const c = UITableCell.text(text)
    c.titleFont = Font.systemFont(14)
    c.titleColor = COLORS.sub
    r.addCell(c)
    table.addRow(r)
  }

  if (g.overdue.length) {
    sectionRow('期限切れ', g.overdue.length, COLORS.overdue)
    for (const t of g.overdue) itemRow(t, 'overdue')
  }
  sectionRow('今日', g.today.length, COLORS.accent)
  if (g.today.length) for (const t of g.today) itemRow(t, 'today')
  else emptyRow('今日のTODOはありません')
  if (g.upcoming.length) {
    sectionRow('今後', g.upcoming.length, COLORS.sub)
    for (const t of g.upcoming) itemRow(t, 'small')
  }
  if (g.doneToday.length) {
    const r = new UITableRow()
    r.height = 48
    r.dismissOnSelect = false
    const c = UITableCell.text(state.showDone ? '✓ 完了済みを隠す' : '✓ 完了済み ' + g.doneToday.length + '件を表示')
    c.titleFont = Font.systemFont(14)
    c.titleColor = COLORS.sub
    r.addCell(c)
    r.onSelect = () => actions.toggleDone()
    table.addRow(r)
    if (state.showDone) for (const t of g.doneToday) itemRow(t, 'done')
  }

  const add = new UITableRow()
  add.height = 60
  add.dismissOnSelect = false
  const ac = UITableCell.text('＋ TODOを追加')
  ac.titleFont = Font.boldSystemFont(17)
  ac.titleColor = COLORS.accent
  ac.centerAligned()
  add.addCell(ac)
  add.onSelect = () => actions.add()
  table.addRow(add)
  return g
}

// 期限の選び方を聞いて { due, allDay } を返す。キャンセル時は null、「変更しない」は undefined
async function askDue(t) {
  const a = new Alert()
  a.title = '期限'
  if (t) a.message = '現在：' + (t.due ? new Date(t.due).toLocaleString() : '期限なし')
  a.addAction('期限なし')
  a.addAction('日付を選ぶ')
  a.addAction('日付と時刻を選ぶ')
  if (t) a.addAction('変更しない')
  a.addCancelAction('キャンセル')
  const i = await a.presentSheet()
  if (i === -1) return null
  if (i === 0) return { due: null, allDay: false }
  if (i === 3) return undefined
  const dp = new DatePicker()
  if (t && t.due) dp.initialDate = new Date(t.due)
  let d
  try {
    d = i === 1 ? await dp.pickDate() : await dp.pickDateAndTime()
  } catch (e) {
    return null // 選択をキャンセルした
  }
  if (!d) return null
  if (i === 1) {
    const x = new Date(d)
    x.setHours(0, 0, 0, 0)
    return { due: x.toISOString(), allDay: true }
  }
  return { due: new Date(d).toISOString(), allDay: false }
}

async function info(title, message) {
  const a = new Alert()
  a.title = title
  a.message = message
  a.addAction('OK')
  await a.presentAlert()
}

async function present(data, ctx) {
  const model = ctx.model
  const state = { todos: data.todos, dismissed: [], showDone: false }
  const table = new UITable()
  table.showSeparators = true
  let busy = false

  async function persist() {
    try {
      await ctx.onMessage({ type: 'save', todos: state.todos, dismissed: state.dismissed })
    } catch (e) {
      console.error('保存エラー: ' + e)
    }
  }

  function rebuild() {
    table.removeAllRows()
    buildRows(table, state, model, ctx.error, actions)
    table.reload()
  }

  // 操作中に別の行をタップしても二重に動かないようにする
  function run(fn) {
    if (busy) return
    busy = true
    Promise.resolve()
      .then(fn)
      .catch(e => console.error('操作エラー: ' + (e && e.message ? e.message : e)))
      .then(() => { busy = false })
  }

  async function changed() {
    await persist()
    rebuild()
  }

  function find(id) {
    return state.todos.find(x => x.id === id)
  }

  async function toggle(id) {
    const t = find(id)
    if (!t) return
    const stamp = new Date().toISOString()
    t.done = !t.done
    t.doneAt = t.done ? stamp : null
    t.updatedAt = stamp
    await changed()
  }

  async function addTodo() {
    const a = new Alert()
    a.title = 'TODOを追加'
    a.addTextField('タイトル', '')
    a.addTextField('メモ（任意）', '')
    a.addAction('次へ')
    a.addCancelAction('キャンセル')
    if ((await a.presentAlert()) === -1) return
    const title = a.textFieldValue(0).trim()
    if (!title) {
      await info('タイトルが空です', 'タイトルを入力してください。')
      return
    }
    const due = await askDue(null)
    if (!due) return
    const stamp = new Date().toISOString()
    state.todos.push({
      id: model.newId(), title: title, due: due.due, allDay: due.allDay, note: a.textFieldValue(1),
      done: false, doneAt: null, source: 'manual', createdAt: stamp, updatedAt: stamp,
    })
    await changed()
  }

  async function edit(t) {
    const isCal = t.source === 'calendar'
    const a = new Alert()
    a.title = 'TODOを編集'
    if (isCal) {
      a.message = t.title + '\n' + model.fmtDue(t, new Date()) + '・' + (t.calendarTitle || 'カレンダー') +
        '\n\nタイトルや日時の変更はカレンダーアプリで行ってください（自動で反映されます）。メモのみ編集できます。'
    } else {
      a.addTextField('タイトル', t.title)
    }
    a.addTextField('メモ', t.note || '')
    a.addAction(isCal ? '保存' : '次へ（期限）')
    a.addCancelAction('キャンセル')
    if ((await a.presentAlert()) === -1) return
    const stamp = new Date().toISOString()
    if (isCal) {
      t.note = a.textFieldValue(0)
      t.updatedAt = stamp
      await changed()
      return
    }
    const title = a.textFieldValue(0).trim()
    if (!title) {
      await info('タイトルが空です', 'タイトルを入力してください。')
      return
    }
    const due = await askDue(t)
    if (due === null) return
    t.title = title
    t.note = a.textFieldValue(1)
    if (due) {
      t.due = due.due
      t.allDay = due.allDay
    }
    t.updatedAt = stamp
    await changed()
  }

  async function remove(t) {
    const a = new Alert()
    a.title = '削除しますか？'
    a.message = t.title + (t.source === 'calendar' ? '\n\nカレンダーの予定は消えません。このTODOは今後取り込まれなくなります。' : '')
    a.addDestructiveAction('削除')
    a.addCancelAction('キャンセル')
    if ((await a.presentAlert()) !== 0) return
    if (t.source === 'calendar') state.dismissed.push({ key: t.eventKey, due: t.due })
    state.todos = state.todos.filter(x => x.id !== t.id)
    await changed()
  }

  async function open(id) {
    const t = find(id)
    if (!t) return
    const a = new Alert()
    a.title = t.title
    a.message = model.fmtDue(t, new Date()) + (t.source === 'calendar' ? '・' + (t.calendarTitle || 'カレンダー') : '') +
      (t.note ? '\n' + t.note : '')
    a.addAction('編集')
    a.addDestructiveAction('削除')
    a.addCancelAction('キャンセル')
    const i = await a.presentSheet()
    if (i === 0) await edit(t)
    else if (i === 1) await remove(t)
  }

  const actions = {
    toggle: id => run(() => toggle(id)),
    open: id => run(() => open(id)),
    add: () => run(addTodo),
    toggleDone: () => { state.showDone = !state.showDone; rebuild() },
  }

  buildRows(table, state, model, ctx.error, actions)
  await table.present(true)
}

module.exports = { present, buildRows }
