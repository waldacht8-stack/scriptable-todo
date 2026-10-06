// PC上でのロジック確認用テスト（Scriptable の API はモック）
// 実行: tests\run-tests.ps1（VS Code 同梱の Node で実行する）
const fs = require('fs')
const path = require('path')
const assert = require('assert')

const SRC = path.join(__dirname, '..', 'src')

// Scriptable の module.exports 形式のファイルを読み込む
function loadModule(rel, globals) {
  const code = fs.readFileSync(path.join(SRC, rel), 'utf8')
  const module = { exports: {} }
  const names = Object.keys(globals || {})
  const fn = new Function('module', ...names, code)
  fn(module, ...names.map(n => globals[n]))
  return module.exports
}

let passed = 0
const asyncTests = []
function test(name, fn) {
  try {
    fn()
    passed++
    console.log('  ok  ' + name)
  } catch (e) {
    console.log('  NG  ' + name)
    console.log(e.stack)
    process.exitCode = 1
  }
}

// --- 構文チェック（トップレベル await があるので async 関数として包む） ---
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
for (const f of ['TODO.js', 'TODO Diag.js', 'TODO Update.js', 'todo-lib/model.js', 'todo-lib/store.js', 'todo-lib/sync.js', 'todo-lib/notify.js', 'todo-lib/widget.js', 'todo-lib/ui.js', 'todo-lib/ui-table.js']) {
  test('構文: ' + f, () => { new AsyncFunction('module', fs.readFileSync(path.join(SRC, f), 'utf8')) })
}

const model = loadModule('todo-lib/model.js')
const at = s => new Date(s) // ローカル時刻で解釈される
const now = at('2026-10-07T12:00')

function todo(over) {
  return Object.assign({ id: model.newId(), title: 't', due: null, allDay: false, note: '', done: false, doneAt: null, source: 'manual', createdAt: '2026-10-01T00:00:00.000Z' }, over)
}

test('分類: 期限切れ/今日/今後/期限なし/完了', () => {
  const todos = [
    todo({ title: '昨日', due: at('2026-10-06T17:00').toISOString() }),
    todo({ title: '今日の朝(過ぎた)', due: at('2026-10-07T09:00').toISOString() }),
    todo({ title: '今日14時', due: at('2026-10-07T14:00').toISOString() }),
    todo({ title: '今日終日', due: at('2026-10-07T00:00').toISOString(), allDay: true }),
    todo({ title: '期限なし' }),
    todo({ title: '明日', due: at('2026-10-08T11:00').toISOString() }),
    todo({ title: '今日完了', done: true, doneAt: at('2026-10-07T08:00').toISOString() }),
    todo({ title: '昨日完了', done: true, doneAt: at('2026-10-06T08:00').toISOString() }),
  ]
  const g = model.categorize(todos, now)
  assert.deepStrictEqual(g.overdue.map(t => t.title), ['昨日', '今日の朝(過ぎた)'])
  assert.deepStrictEqual(g.today.map(t => t.title), ['今日終日', '今日14時', '期限なし'])
  assert.deepStrictEqual(g.upcoming.map(t => t.title), ['明日'])
  assert.deepStrictEqual(g.doneToday.map(t => t.title), ['今日完了'])
  assert.deepStrictEqual(g.stats, { remaining: 5, done: 1, total: 6 })
  assert.strictEqual(model.nextItem(g, now).title, '今日14時')
})

test('期限ラベル', () => {
  assert.strictEqual(model.fmtDue(todo({ due: at('2026-10-07T14:00').toISOString() }), now), '14:00')
  assert.strictEqual(model.fmtDue(todo({ due: at('2026-10-06T17:00').toISOString() }), now), '昨日 17:00')
  assert.strictEqual(model.fmtDue(todo({ due: at('2026-10-08T11:00').toISOString() }), now), '明日 11:00')
  assert.strictEqual(model.fmtDue(todo({ due: at('2026-10-12T00:00').toISOString(), allDay: true }), now), '10/12（月）')
  assert.strictEqual(model.fmtDue(todo({ due: at('2026-10-07T00:00').toISOString(), allDay: true }), now), '終日')
  assert.strictEqual(model.fmtDue(todo({}), now), '時間指定なし')
  assert.strictEqual(model.fmtDate(now), '10月7日（水）')
})

test('カレンダー取り込み: 追加・更新・削除・再取り込みしない', () => {
  const start = model.startOfDay(now)
  const end = model.addDays(start, 14)
  const data = { todos: [], dismissed: {} }
  const ev = (key, title, s) => ({ key: key, title: title, due: at(s).toISOString(), allDay: false, calendarTitle: '仕事' })

  let r = model.mergeEvents(data, [ev('a', '歯医者', '2026-10-07T14:00'), ev('b', '会議', '2026-10-09T10:00')], start, end, now)
  assert.deepStrictEqual(r, { added: 2, updated: 0, removed: 0 })

  // タイトル変更は反映、b は予定が消えたので削除
  r = model.mergeEvents(data, [ev('a', '歯医者（変更）', '2026-10-07T14:00')], start, end, now)
  assert.deepStrictEqual(r, { added: 0, updated: 1, removed: 1 })
  assert.strictEqual(data.todos.length, 1)
  assert.strictEqual(data.todos[0].title, '歯医者（変更）')

  // 完了済みは予定が変わっても消さない・書き換えない
  data.todos[0].done = true
  r = model.mergeEvents(data, [], start, end, now)
  assert.strictEqual(r.removed, 0)
  assert.strictEqual(data.todos.length, 1)

  // アプリで削除した予定は再取り込みしない
  data.dismissed['c'] = at('2026-10-08T10:00').toISOString()
  r = model.mergeEvents(data, [ev('c', '飲み会', '2026-10-08T10:00')], start, end, now)
  assert.strictEqual(r.added, 0)

  // 範囲外（過去）の dismissed は掃除される
  data.dismissed['old'] = at('2026-10-01T10:00').toISOString()
  model.mergeEvents(data, [], start, end, now)
  assert.ok(!('old' in data.dismissed))
  assert.ok('c' in data.dismissed)
})

test('手動TODOはカレンダー同期で消えない', () => {
  const start = model.startOfDay(now)
  const data = { todos: [todo({ title: '手動', due: at('2026-10-08T10:00').toISOString() })], dismissed: {} }
  model.mergeEvents(data, [], start, model.addDays(start, 14), now)
  assert.strictEqual(data.todos.length, 1)
})

test('完了から30日以上たったTODOを削除', () => {
  const data = { todos: [todo({ done: true, doneAt: at('2026-09-01T10:00').toISOString() }), todo({ done: true, doneAt: at('2026-10-01T10:00').toISOString() })] }
  model.pruneDone(data, now)
  assert.strictEqual(data.todos.length, 1)
})

test('通知計画: 朝の一覧と30分前リマインド', () => {
  const data = {
    settings: { remindMinutes: 30, morningHour: 7, morningMinute: 0 },
    todos: [
      todo({ id: 'x', title: '歯医者', due: at('2026-10-07T14:00').toISOString() }),
      todo({ id: 'y', title: '過ぎた', due: at('2026-10-07T12:10').toISOString() }), // 30分前は過去なので通知しない
      todo({ id: 'z', title: '明日', due: at('2026-10-08T10:00').toISOString() }),
      todo({ id: 'w', title: '終日', due: at('2026-10-08T00:00').toISOString(), allDay: true }),
    ],
  }
  const plans = model.planNotifications(data, now)
  const ids = plans.map(p => p.id)
  assert.deepStrictEqual(ids, ['todo-morning-1', 'todo-morning-2', 'todo-remind-x', 'todo-remind-z'])
  const remind = plans.find(p => p.id === 'todo-remind-x')
  assert.strictEqual(new Date(remind.at).getTime(), at('2026-10-07T13:30').getTime())
  assert.strictEqual(remind.title, '30分後：歯医者')
  const morning = plans.find(p => p.id === 'todo-morning-1')
  assert.strictEqual(new Date(morning.at).getTime(), at('2026-10-08T07:00').getTime())
  assert.ok(morning.body.indexOf('期限切れ') >= 0, morning.body)
})

test('画面HTMLの生成と埋め込みスクリプトの構文', () => {
  const ui = loadModule('todo-lib/ui.js', { WebView: function () {}, Timer: function () {} })
  const html = ui.buildHTML({ todos: [todo({ title: '</script><b>x' })] }, model, null)
  const m = html.match(/<script>([\s\S]*)<\/script>/)
  assert.ok(m, 'script タグがある')
  assert.ok(html.indexOf('</script><b>x') < 0, 'データ中の </script> はエスケープされる')
  new Function(m[1]) // 構文エラーなら例外
})

// 画面スクリプトを疑似DOMで動かし、描画・追加・完了・削除の流れを確認する
test('画面の動作: 描画/追加/完了/削除', () => {
  const ui = loadModule('todo-lib/ui.js', { WebView: function () {}, Timer: function () {} })
  const cal = todo({ id: 'cal1', title: '歯医者', due: new Date(Date.now() + 3600e3).toISOString(), source: 'calendar', eventKey: 'ev1' })
  const html = ui.buildHTML({ todos: [cal] }, model, 'テストエラー')
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1]
  const els = {}
  const el = id => els[id] || (els[id] = { id: id, innerHTML: '', value: '', focus() {} })
  let onClick = null
  const document = { getElementById: el, addEventListener: (type, fn) => { onClick = fn } }
  const window = { location: {} }
  const click = (act, id) => {
    const target = { classList: { add() {} }, getAttribute: n => (n === 'data-act' ? act : n === 'data-id' ? id || null : null), textContent: '' }
    onClick({ target: { closest: () => target } })
  }
  new Function('document', 'window', 'setTimeout', 'setInterval', script)(document, window, fn => fn(), () => 0)
  assert.ok(els.app.innerHTML.indexOf('歯医者') >= 0, '一覧に表示')
  assert.ok(els.app.innerHTML.indexOf('テストエラー') >= 0, 'エラーバナー表示')

  // 追加
  click('add')
  el('f-title').value = '牛乳を買う'
  el('f-date').value = ''
  el('f-time').value = '18:00'
  el('f-note').value = ''
  click('save')
  let saved = JSON.parse(window.__drain())
  assert.strictEqual(saved.todos.length, 2)
  const milk = saved.todos.find(t => t.title === '牛乳を買う')
  assert.strictEqual(new Date(milk.due).getHours(), 18)
  assert.strictEqual(window.location.href, 'todoapp://flush', '保存の合図を送る')

  // 完了
  click('toggle', milk.id)
  saved = JSON.parse(window.__drain())
  assert.strictEqual(saved.todos.find(t => t.id === milk.id).done, true)
  assert.ok(els.app.innerHTML.indexOf('完了済み 1件') >= 0)

  // カレンダー由来の削除は2回押しで確定し、dismissed に入る
  click('edit', 'cal1')
  click('delete')
  assert.strictEqual(window.__drain(), '', '1回目は確定しない')
  click('delete')
  saved = JSON.parse(window.__drain())
  assert.strictEqual(saved.todos.length, 1)
  assert.deepStrictEqual(saved.dismissed.map(d => d.key), ['ev1'])
})

// UITable 版の予備画面：Scriptable の UI クラスを最小限モックして行の組み立てと操作を確認する
function tableMocks(script) {
  const log = { presented: false, alerts: [] }
  const queue = script.slice() // Alert の応答を順に返す: { index, fields }
  class Color { constructor(hex) { this.hex = hex } static dynamic(a) { return a } }
  const Font = { systemFont: s => ({ s }), boldSystemFont: s => ({ s }), semiboldSystemFont: s => ({ s }) }
  class UITableCell {
    static text(title, subtitle) { const c = new UITableCell(); c.type = 'text'; c.title = title; c.subtitle = subtitle; return c }
    static button(title) { const c = new UITableCell(); c.type = 'button'; c.title = title; return c }
    leftAligned() {} centerAligned() {} rightAligned() {}
  }
  class UITableRow { constructor() { this.cells = [] } addCell(c) { this.cells.push(c) } }
  class UITable {
    constructor() { this.rows = []; log.table = this }
    addRow(r) { this.rows.push(r) }
    removeAllRows() { this.rows = [] }
    reload() { log.reloaded = (log.reloaded || 0) + 1 }
    async present() { log.presented = true }
  }
  class Alert {
    constructor() { this.fields = []; this.actions = [] }
    addTextField(p, v) { this.fields.push(v || '') }
    addAction(a) { this.actions.push(a) }
    addDestructiveAction(a) { this.actions.push(a) }
    addCancelAction() {}
    textFieldValue(i) { return this.fields[i] }
    async answer() {
      log.alerts.push(this.title)
      const r = queue.shift() || { index: -1 }
      if (r.fields) this.fields = r.fields
      return r.index
    }
    presentAlert() { return this.answer() }
    presentSheet() { return this.answer() }
    present() { return this.answer() }
  }
  class DatePicker { async pickDate() { return new Date(2026, 9, 10, 15, 30) } async pickDateAndTime() { return new Date(2026, 9, 10, 15, 30) } }
  const SFSymbol = { named: () => ({ image: {} }) }
  return { log, queue, globals: { Color, Font, UITableCell, UITableRow, UITable, Alert, DatePicker, SFSymbol } }
}
const flush = () => new Promise(r => setTimeout(r, 0))
const texts = table => table.rows.map(r => r.cells.map(c => c.title + (c.subtitle ? '|' + c.subtitle : '')).join(' ')).join('\n')

asyncTests.push(['UITable画面: 行の組み立て/追加/完了/削除', async () => {
  const m = tableMocks([])
  const ui = loadModule('todo-lib/ui-table.js', m.globals)
  const t0 = Date.now()
  const data = {
    todos: [
      todo({ id: 'o', title: '期限切れ', due: new Date(t0 - 86400e3 * 2).toISOString() }),
      todo({ id: 'n', title: '期限なし' }),
      todo({ id: 'u', title: '来週', due: new Date(t0 + 86400e3 * 7).toISOString() }),
      todo({ id: 'cal1', title: '歯医者', due: new Date(t0 + 86400e3 * 3).toISOString(), source: 'calendar', eventKey: 'ev1' }),
      todo({ id: 'd', title: '済み', done: true, doneAt: new Date().toISOString() }),
    ],
  }
  const saves = []
  await ui.present(data, { model: model, error: 'テストエラー', onMessage: async msg => { saves.push(JSON.parse(JSON.stringify(msg))) } })
  const table = m.log.table
  assert.ok(m.log.presented, 'present された')
  let s = texts(table)
  for (const w of ['今日 残り2件', '1 / 3 件 完了', 'テストエラー', '期限切れ', '今後', 'カレンダー', '完了済み 1件を表示', '＋ TODOを追加']) assert.ok(s.indexOf(w) >= 0, w + '\n' + s)
  const rowOf = title => table.rows.find(r => r.cells.some(c => c.title === title))

  // 完了済みの開閉
  table.rows.find(r => r.cells[0].title.indexOf('完了済み') >= 0).onSelect(0)
  assert.ok(texts(table).indexOf('完了済みを隠す') >= 0)

  // 完了トグル
  rowOf('期限なし').cells[0].onTap()
  await flush(); await flush()
  assert.strictEqual(saves.length, 1)
  assert.ok(saves[0].todos.find(t => t.id === 'n').doneAt)
  assert.ok(m.log.reloaded >= 1)

  // 追加：タイトル入力 → 日付と時刻を選ぶ
  m.queue.push({ index: 0, fields: ['牛乳を買う', ''] }, { index: 2 })
  rowOf('＋ TODOを追加').onSelect(0)
  for (let i = 0; i < 5; i++) await flush()
  const milk = saves[saves.length - 1].todos.find(t => t.title === '牛乳を買う')
  assert.ok(milk, '追加された')
  assert.strictEqual(milk.source, 'manual')
  assert.strictEqual(new Date(milk.due).getHours(), 15)
  assert.strictEqual(milk.allDay, false)

  // カレンダー由来の削除：メニュー → 削除 → 確認
  m.queue.push({ index: 1 }, { index: 0 })
  rowOf('歯医者').onSelect(0)
  for (let i = 0; i < 5; i++) await flush()
  const last = saves[saves.length - 1]
  assert.ok(!last.todos.some(t => t.id === 'cal1'))
  assert.deepStrictEqual(last.dismissed.map(d => d.key), ['ev1'])

  // 手動TODOの編集：タイトル変更 → 期限なし
  m.queue.push({ index: 0 }, { index: 0, fields: ['来週（改）', 'メモ'] }, { index: 0 })
  rowOf('来週').onSelect(0)
  for (let i = 0; i < 6; i++) await flush()
  const ed = saves[saves.length - 1].todos.find(t => t.id === 'u')
  assert.strictEqual(ed.title, '来週（改）')
  assert.strictEqual(ed.due, null)
  assert.strictEqual(ed.note, 'メモ')
}])

;(async () => {
  for (const [name, fn] of asyncTests) {
    try {
      await fn()
      passed++
      console.log('  ok  ' + name)
    } catch (e) {
      console.log('  NG  ' + name)
      console.log(e.stack)
      process.exitCode = 1
    }
  }
  console.log('\n' + passed + ' 件成功' + (process.exitCode ? '（失敗あり）' : ''))
})()
