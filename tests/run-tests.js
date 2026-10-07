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

test('カレンダー取り込み: 識別子が変わったアプリ登録の予定はタイトル・日時で照合して付け替える', () => {
  const start = model.startOfDay(now)
  const due = at('2026-10-08T15:00').toISOString()
  const data = { todos: [todo({ title: '打ち合わせ', due: due, source: 'calendar', eventKey: 'null@' + due })], dismissed: {} }
  const r = model.mergeEvents(data, [{ key: 'real-id@' + due, title: '打ち合わせ', due: due, allDay: false, calendarTitle: '仕事' }], start, model.addDays(start, 14), now)
  assert.deepStrictEqual(r, { added: 0, updated: 0, removed: 0 })
  assert.strictEqual(data.todos.length, 1)
  assert.strictEqual(data.todos[0].eventKey, 'real-id@' + due)
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

// ===== Scriptable 模擬環境で TODO.js を丸ごと実行する（tests/scriptable-mock.js） =====
const { createScriptableEnv } = require('./scriptable-mock')
const DATA_FILE = '/iCloud/Documents/todo-data/todo-data.json'
const DAY = 86400e3

function todayStart() {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

// 期限切れ / 今日(時刻) / 今日(終日) / 期限なし / 今後 / 完了 を1件ずつ
function sampleData() {
  const n = Date.now()
  const t0 = todayStart()
  const iso = x => new Date(x).toISOString()
  return {
    version: 1,
    todos: [
      todo({ id: 'od', title: '期限切れタスク', due: iso(n - DAY) }),
      todo({ id: 'tt', title: '今日の時刻つき', due: iso(Math.min(n + 3600e3, t0 + DAY - 60e3)) }),
      todo({ id: 'ad', title: '今日の終日', due: iso(t0), allDay: true }),
      todo({ id: 'n1', title: '期限なしタスク' }),
      todo({ id: 'up', title: '明後日の予定', due: iso(t0 + 2 * DAY + 10 * 3600e3) }),
      todo({ id: 'dn', title: '完了済み', done: true, doneAt: iso(n - 60e3) }),
    ],
    dismissed: {},
    settings: {},
    meta: {},
  }
}

function sampleEvents() {
  const t0 = todayStart()
  return [
    { identifier: 'ev-1', title: '歯医者', startDate: new Date(t0 + 2 * DAY + 14 * 3600e3), endDate: new Date(t0 + 2 * DAY + 15 * 3600e3), calendar: '仕事' },
    { identifier: 'ev-2', title: '出張', startDate: new Date(t0 + 3 * DAY), endDate: new Date(t0 + 4 * DAY), isAllDay: true, calendar: '仕事' },
    { identifier: 'hol', title: '祝日', startDate: new Date(t0 + DAY), endDate: new Date(t0 + 2 * DAY), isAllDay: true, calendar: '日本の祝日' },
    { identifier: 'ev-old', title: '先週から続く', startDate: new Date(t0 - 2 * DAY), endDate: new Date(t0 + DAY), calendar: '仕事' },
  ]
}

async function runTodo(opts, data) {
  const env = createScriptableEnv(opts)
  if (data !== undefined) env.files.write(DATA_FILE, typeof data === 'string' ? data : JSON.stringify(data))
  try {
    await env.run('TODO.js')
  } finally {
    env.dispose()
  }
  return env
}

// 例外・エラー表示・後始末漏れがないこと
function assertClean(env) {
  assert.deepStrictEqual(env.uncaught.map(e => e.stack || String(e)), [], 'タイマー内の例外')
  assert.deepStrictEqual(env.errors(), [], 'console.error')
  assert.deepStrictEqual(env.alerts.map(a => a.title + ': ' + a.message), [], 'エラーのアラート')
  for (const p of env.pages) assert.deepStrictEqual(p.errors.map(e => e.stack || String(e)), [], '画面内の例外')
  assert.ok(env.script.completed, 'Script.complete() が呼ばれた')
}

function savedData(env) {
  return JSON.parse(env.files.read(DATA_FILE))
}

const FAMILIES = ['small', 'medium', 'large', 'extraLarge', 'accessoryCircular', 'accessoryRectangular', 'accessoryInline']
for (const family of FAMILIES) {
  for (const kind of ['空データ', 'サンプル']) {
    asyncTests.push(['模擬実行 ウィジェット ' + family + '（' + kind + '）', async () => {
      const sample = kind === 'サンプル'
      const env = await runTodo({ runsInWidget: true, widgetFamily: family, events: sample ? sampleEvents() : [] }, sample ? sampleData() : undefined)
      assertClean(env)
      const w = env.script.widget
      assert.ok(w, 'Script.setWidget にウィジェットが渡った')
      const texts = env.widgetTexts(w)
      assert.ok(texts.length > 0, 'テキストがある')
      assert.ok(!(texts[0] === 'TODO' && texts.length === 2), 'エラー用ウィジェットになった: ' + texts[1])
      assert.ok(!texts.some(t => t.indexOf('同期エラー') >= 0), '同期エラー表示\n' + env.widgetTree(w))
      assert.strictEqual(w.url, 'scriptable:///run/TODO')
      assert.ok(w.refreshAfterDate > new Date())
      if (sample && (family === 'large' || family === 'extraLarge')) {
        const all = texts.join('\n')
        for (const s of ['期限切れタスク', '今日の終日', '期限なしタスク']) assert.ok(all.indexOf(s) >= 0, s + '\n' + env.widgetTree(w))
      }
      if (sample) {
        // ウィジェット実行でもカレンダー同期・保存が行われる
        const titles = savedData(env).todos.map(t => t.title)
        assert.ok(titles.indexOf('歯医者') >= 0, titles.join(','))
      }
    }])
  }
}

asyncTests.push(['模擬実行 ウィジェット: データファイルが壊れていたらエラー表示ウィジェット', async () => {
  const env = await runTodo({ runsInWidget: true, widgetFamily: 'small' }, '{ broken')
  const texts = env.widgetTexts(env.script.widget)
  assert.strictEqual(texts[0], 'TODO')
  assert.ok(texts[1].indexOf('データファイルが壊れています') >= 0, texts[1])
  assert.ok(env.files.list().some(p => p.indexOf('todo-data.json.broken-') >= 0), '退避ファイル')
}])

asyncTests.push(['模擬実行 バックグラウンド同期: 予定取り込みと通知予約', async () => {
  const env = createScriptableEnv({ shortcutParameter: 'sync', events: sampleEvents() })
  env.files.write(DATA_FILE, JSON.stringify(sampleData()))
  // 以前の予約（このアプリ分は消える・他のスクリプトの分は残る）
  env.notifications.pending.set('todo-remind-old', { identifier: 'todo-remind-old', triggerDate: new Date(Date.now() + DAY) })
  env.notifications.pending.set('other-1', { identifier: 'other-1', triggerDate: new Date(Date.now() + DAY) })
  await env.run('TODO.js')
  env.dispose()
  assertClean(env)
  assert.strictEqual(env.script.output, 'ok')
  const data = savedData(env)
  const titles = data.todos.map(t => t.title)
  assert.ok(titles.indexOf('歯医者') >= 0 && titles.indexOf('出張') >= 0, titles.join(','))
  assert.ok(titles.indexOf('祝日') < 0, '除外カレンダーは取り込まない')
  assert.ok(titles.indexOf('先週から続く') < 0, '前日から続く予定は取り込まない')
  const ev1 = data.todos.find(t => t.title === '歯医者')
  assert.strictEqual(ev1.source, 'calendar')
  assert.strictEqual(ev1.calendarTitle, '仕事')
  assert.ok(data.meta.lastSync)
  const ids = Array.from(env.notifications.pending.keys())
  assert.ok(ids.indexOf('todo-remind-old') < 0, '古い予約は消える')
  assert.ok(ids.indexOf('other-1') >= 0, '他の予約は残す')
  assert.ok(ids.indexOf('todo-remind-' + ev1.id) >= 0, ids.join(','))
  assert.ok(ids.some(id => id.indexOf('todo-morning-') === 0), ids.join(','))
  const rec = env.notifications.pending.get('todo-remind-' + ev1.id)
  assert.strictEqual(rec.openURL, 'scriptable:///run/TODO')
  assert.strictEqual(rec.triggerDate.getTime(), new Date(ev1.due).getTime() - 30 * 60000)
  assert.ok(env.files.exists('/iCloud/Documents/todo-data/todo-data.backup.json'), '上書き前にバックアップ')
}])

asyncTests.push(['模擬実行 ショートカットから Parameter なしで実行しても同期モードで動く（アラートを出さない）', async () => {
  const env = await runTodo({ runsWithSiri: true, events: sampleEvents() }, sampleData())
  assert.deepStrictEqual(env.uncaught, [])
  assert.strictEqual(env.alerts.length, 0, 'アラートは出さない')
  assert.strictEqual(env.script.output, 'ok')
  assert.strictEqual(env.pages.length, 0, '画面は開かない')
}])

asyncTests.push(['模擬実行 バックグラウンド同期: カレンダー失敗時はエラー通知', async () => {
  const env = await runTodo({ shortcutParameter: 'sync', calendarError: new Error('アクセス拒否') }, sampleData())
  assert.deepStrictEqual(env.uncaught, [])
  assert.ok(String(env.script.output).indexOf('error') === 0, String(env.script.output))
  assert.ok(env.script.output.indexOf('アクセス拒否') >= 0)
  assert.ok(env.notifications.delivered.some(n => n.identifier === 'todo-error'), 'エラー通知がすぐ配信された')
  assert.ok(savedData(env).meta.lastErrorAt)
}])

asyncTests.push(['模擬実行 バックグラウンド同期: iCloud 未ダウンロードのファイルを取得して読む', async () => {
  const env = createScriptableEnv({ shortcutParameter: 'sync' })
  env.files.write(DATA_FILE, JSON.stringify(sampleData()), { downloaded: false })
  await env.run('TODO.js')
  env.dispose()
  assertClean(env)
  assert.strictEqual(env.script.output, 'ok')
  assert.strictEqual(savedData(env).todos.length, sampleData().todos.length)
}])

asyncTests.push(['模擬実行 アプリ: 表示 → 完了・追加 → 保存', async () => {
  let seen = null
  const env = await runTodo({
    events: sampleEvents(),
    onWebViewPresent: async (page, env) => {
      seen = page.text()
      // 完了チェック（350ms 後に保存 → todoapp://flush → __drain で回収）
      page.click('toggle', 'n1')
      await env.waitFor(() => savedData(env).todos.some(t => t.id === 'n1' && t.done), 3000, '完了の保存')
      // 追加
      page.click('add')
      await env.wait(100) // 入力欄にフォーカスが移るまで待つ（人の操作より速く押さない）
      page.window.document.getElementById('f-title').value = '牛乳を買う'
      page.click('save')
      await env.waitFor(() => savedData(env).todos.some(t => t.title === '牛乳を買う'), 3000, '追加の保存')
    },
  }, sampleData())
  assertClean(env)
  for (const s of ['期限切れタスク', '今日の時刻つき', '歯医者', '残り']) assert.ok(seen.indexOf(s) >= 0, s)
  const page = env.pages[0]
  assert.ok(page.navigations.some(n => n.url === 'todoapp://flush' && !n.allowed), '合図のナビゲーションは止める')
  const data = savedData(env)
  assert.ok(data.todos.some(t => t.title === '歯医者'), 'カレンダー同期済み')
  assert.ok(data.todos.find(t => t.id === 'n1').doneAt)
  assert.strictEqual(data.todos.find(t => t.title === '牛乳を買う').source, 'manual')
  assert.ok(!Array.from(env.timers).some(t => t.repeats), '定期回収タイマーは止まっている')
}])

asyncTests.push(['模擬実行 アプリ: 「カレンダーにも登録」で予定が作られ、次の同期で重複しない', async () => {
  const start = new Date()
  start.setDate(start.getDate() + 2)
  const ymd = start.getFullYear() + '-' + String(start.getMonth() + 1).padStart(2, '0') + '-' + String(start.getDate()).padStart(2, '0')
  let html = ''
  const env = await runTodo({
    events: sampleEvents(),
    onWebViewPresent: async (page, env) => {
      page.click('add')
      await env.wait(100)
      html = page.window.document.getElementById('sheet').innerHTML
      const doc = page.window.document
      doc.getElementById('f-title').value = '打ち合わせ'
      doc.getElementById('f-date').value = ymd
      doc.getElementById('f-time').value = '15:00'
      doc.getElementById('f-cal').checked = true
      page.click('save')
      await env.waitFor(() => env.savedEvents.length === 1 && savedData(env).todos.some(t => t.title === '打ち合わせ' && t.source === 'calendar'), 3000, '予定の作成')
    },
  }, sampleData())
  assertClean(env)
  assert.ok(html.indexOf('カレンダーにも予定として登録') >= 0, '追加画面にチェックが出る')
  const ev = env.savedEvents[0]
  assert.strictEqual(ev.title, '打ち合わせ')
  assert.strictEqual(ev.startDate.getHours(), 15)
  assert.strictEqual(ev.endDate.getTime() - ev.startDate.getTime(), 3600 * 1000, '1時間の予定')
  const todo = savedData(env).todos.find(t => t.title === '打ち合わせ')
  assert.ok(!todo.pendingEvent && todo.eventKey, 'カレンダー由来に切り替わる')

  // 作った予定を含めて同期しても TODO は1件のまま、予定も二重に作られない
  const env2 = createScriptableEnv({ shortcutParameter: 'sync', events: env.options.events })
  env2.files.write(DATA_FILE, env.files.read(DATA_FILE))
  await env2.run('TODO.js')
  env2.dispose()
  assert.strictEqual(env2.script.output, 'ok')
  assert.strictEqual(savedData(env2).todos.filter(t => t.title === '打ち合わせ').length, 1)
  assert.strictEqual(env2.savedEvents.length, 0)
}])

asyncTests.push(['模擬実行 アプリ: 閉じる直前の変更も回収される', async () => {
  const env = await runTodo({
    onWebViewPresent: async (page, env) => {
      page.click('add')
      await env.wait(100) // 入力欄にフォーカスが移るまで待つ（人の操作より速く押さない）
      page.window.document.getElementById('f-title').value = '閉じる直前'
      page.click('save') // すぐ閉じる
    },
  }, sampleData())
  assertClean(env)
  assert.ok(savedData(env).todos.some(t => t.title === '閉じる直前'))
}])

asyncTests.push(['模擬実行 アプリ: 閉じた後に WebView が応答しなくても終了する', async () => {
  const t = Date.now()
  const env = await runTodo({ evaluateAfterClose: 'hang' }, sampleData())
  assertClean(env)
  assert.ok(Date.now() - t < 5000)
}])

asyncTests.push(['模擬実行 アプリ: カレンダー失敗は画面のエラー表示になる', async () => {
  let seen = ''
  const env = await runTodo({ calendarError: new Error('拒否'), onWebViewPresent: async page => { seen = page.text() } })
  assertClean(env)
  assert.ok(seen.indexOf('カレンダーを読み込めませんでした') >= 0, seen)
  assert.ok(env.files.exists(DATA_FILE), '空データでも保存される')
}])

asyncTests.push(['模擬実行 アプリ（TODO Lite / UITable）', async () => {
  let rows = 0
  const env = await runTodo({ scriptName: 'TODO Lite', events: sampleEvents(), onTablePresent: async table => { rows = table.rows.length } }, sampleData())
  assertClean(env)
  assert.strictEqual(env.webViews.length, 0)
  assert.ok(rows > 5, String(rows))
}])

asyncTests.push(['模擬実行 store: ファイルなし → 既定値 / 壊れたJSON → 退避して例外', async () => {
  let env = createScriptableEnv()
  let store = env.importModule('todo-lib/store')
  const d = await store.load()
  assert.strictEqual(JSON.stringify(d.todos), '[]')
  assert.strictEqual(d.settings.remindMinutes, 30)
  assert.strictEqual(JSON.stringify(d.meta), '{"lastSync":null,"lastErrorAt":null}')
  store.save(d)
  assert.deepStrictEqual(savedData(env).todos, [])
  env.dispose()

  env = createScriptableEnv()
  env.files.write(DATA_FILE, '{"todos": [')
  store = env.importModule('todo-lib/store')
  await assert.rejects(() => store.load(), /データファイルが壊れています/)
  const broken = env.files.list().filter(p => p.indexOf(DATA_FILE + '.broken-') === 0)
  assert.strictEqual(broken.length, 1)
  assert.strictEqual(env.files.read(broken[0]), '{"todos": [')
  assert.strictEqual(env.files.read(DATA_FILE), '{"todos": [', '元ファイルは上書きしない')
  env.dispose()
}])

asyncTests.push(['模擬環境: 存在しない API・不正な型は例外になる', async () => {
  const env = createScriptableEnv()
  const w = new env.globals.ListWidget()
  assert.throws(() => w.layoutHorizontally(), /ListWidget.layoutHorizontally/)
  assert.throws(() => { w.textColor = new env.globals.Color('#000') }, /代入できる/)
  assert.throws(() => { w.addText('x').textColor = '#000' }, /Color が必要/)
  assert.throws(() => env.globals.Font.boldFont(12), /Font.boldFont/)
  env.dispose()
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
