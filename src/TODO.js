// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: blue; icon-glyph: check-square;
// TODO.js — エントリーポイント（Scriptable のスクリプト一覧に出るのはこのファイルだけ）
//   アプリから実行      → カレンダー同期 → 一覧画面
//   ウィジェットから実行 → カレンダー同期 → 通知再予約 → ウィジェット描画
//   ショートカットから「sync」を渡して実行 → カレンダー同期 → 通知再予約（毎朝の保険）

const store = importModule('todo-lib/store')
const model = importModule('todo-lib/model')
const sync = importModule('todo-lib/sync')
const notify = importModule('todo-lib/notify')
const widget = importModule('todo-lib/widget')
// 「TODO Lite」という名前で実行されたら、WebView を使わない予備画面（UITable）を使う
const ui = Script.name().indexOf('Lite') >= 0 ? importModule('todo-lib/ui-table') : importModule('todo-lib/ui')

function messageOf(e) {
  return e && e.message ? e.message : String(e)
}

// 応答が返らない処理で全体が止まらないよう、制限時間を超えたら失敗扱いにする
function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const t = new Timer()
    t.timeInterval = ms
    t.schedule(() => reject(new Error(label + ' が ' + (ms / 1000) + ' 秒以内に終わりませんでした')))
    promise.then(v => { t.invalidate(); resolve(v) }, e => { t.invalidate(); reject(e) })
  })
}

// カレンダー同期と通知の再予約。失敗してもTODOの表示は止めず、エラー文を返す
async function refresh(data, now) {
  let error = null
  try {
    console.log('カレンダー同期 開始')
    const r = await withTimeout(sync.syncCalendar(data, now, model), 10000, 'カレンダー同期')
    console.log('カレンダー同期 完了: ' + JSON.stringify(r))
  } catch (e) {
    error = 'カレンダーを読み込めませんでした（' + messageOf(e) + '）。設定 > Scriptable でカレンダーへのアクセスを許可してください。'
  }
  try {
    console.log('通知予約 開始')
    const n = await withTimeout(notify.reschedule(data, now, model), 10000, '通知予約')
    console.log('通知予約 完了: ' + n + '件')
  } catch (e) {
    error = error || '通知を予約できませんでした（' + messageOf(e) + '）。設定 > Scriptable で通知を許可してください。'
  }
  return error
}

async function runWidget() {
  const now = new Date()
  let w
  try {
    const data = await store.load()
    const error = await refresh(data, now)
    if (error) await notify.error(data, error, now)
    store.save(data)
    w = widget.build(data, config.widgetFamily, now, model, error)
  } catch (e) {
    w = widget.buildError(messageOf(e))
  }
  Script.setWidget(w)
}

async function runBackground() {
  const now = new Date()
  try {
    const data = await store.load()
    const error = await refresh(data, now)
    if (error) await notify.error(data, error, now)
    store.save(data)
    Script.setShortcutOutput(error ? 'error: ' + error : 'ok')
  } catch (e) {
    const n = new Notification()
    n.identifier = 'todo-error'
    n.title = 'TODO：処理エラー'
    n.body = messageOf(e)
    await n.schedule()
    Script.setShortcutOutput('error: ' + messageOf(e))
  }
}

async function showError(title, e) {
  const a = new Alert()
  a.title = title
  a.message = messageOf(e) + (e && e.stack ? '\n\n' + e.stack : '')
  a.addAction('OK')
  await a.present()
}

let step = '開始'
async function runApp() {
  const now = new Date()
  step = 'データ読み込み'
  console.log(step)
  const data = await store.load()
  step = 'カレンダー同期・通知予約'
  console.log(step)
  const error = await refresh(data, now)
  step = 'データ保存'
  console.log(step)
  store.save(data)
  step = '画面表示'
  console.log(step)
  await ui.present(data, {
    model: model,
    error: error,
    onMessage: async msg => {
      if (msg.type !== 'save') return
      data.todos = msg.todos
      for (const d of msg.dismissed) data.dismissed[d.key] = d.due
      store.save(data)
      try {
        await withTimeout(notify.reschedule(data, new Date(), model), 10000, '通知予約')
      } catch (e) {
        // 通知の失敗は次回の同期で再試行される
      }
    },
  })
}

const mode = String(args.shortcutParameter || (args.queryParameters && args.queryParameters.mode) || '')
if (config.runsInWidget) await runWidget()
else if (mode === 'sync') await runBackground()
else {
  try {
    await runApp()
  } catch (e) {
    console.error(step + ': ' + messageOf(e))
    await showError('エラー（' + step + '）', e)
  }
}
Script.complete()
