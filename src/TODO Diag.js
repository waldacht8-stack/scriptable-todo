// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: red; icon-glyph: stethoscope;
// TODO Diag.js — 1段階ずつ実行して、どこで止まるかを表示する診断スクリプト
const DIAG_VERSION = 'diag-1'
const results = []

function msg(e) { return e && e.message ? e.message : String(e) }

function timeout(ms, label) {
  return new Promise((_, reject) => {
    const t = new Timer()
    t.timeInterval = ms
    t.schedule(() => reject(new Error(label + ': ' + ms / 1000 + '秒で応答なし')))
  })
}

async function step(name, fn, ms) {
  const started = Date.now()
  try {
    const v = await Promise.race([fn(), timeout(ms || 10000, name)])
    results.push('OK  ' + name + (v !== undefined ? '：' + v : '') + '（' + (Date.now() - started) + 'ms）')
    return v
  } catch (e) {
    results.push('NG  ' + name + '：' + msg(e))
    return undefined
  }
}

async function alert(title, message, buttons) {
  const a = new Alert()
  a.title = title
  a.message = message
  for (const b of buttons || ['OK']) a.addAction(b)
  return a.presentAlert()
}

await alert('診断開始', 'バージョン ' + DIAG_VERSION + '\n各段階を順に実行します。途中で画面が2回開くので、右上の「閉じる」で閉じてください。')

const fm = FileManager.iCloud()
const dir = fm.documentsDirectory()

await step('配置ファイルの確認', async () => {
  const names = ['TODO.js', 'todo-lib/model.js', 'todo-lib/store.js', 'todo-lib/sync.js', 'todo-lib/notify.js', 'todo-lib/ui.js', 'todo-lib/widget.js', 'todo-lib/ui-table.js']
  const out = []
  for (const n of names) {
    const p = fm.joinPath(dir, n)
    if (!fm.fileExists(p)) { out.push(n + '=なし'); continue }
    if (!fm.isFileDownloaded(p)) await fm.downloadFileFromiCloud(p)
    const d = fm.modificationDate(p)
    out.push(n.replace('todo-lib/', '') + '=' + (d ? (d.getMonth() + 1) + '/' + d.getDate() + ' ' + d.getHours() + ':' + ('0' + d.getMinutes()).slice(-2) : '?'))
  }
  const ui = fm.readString(fm.joinPath(dir, 'todo-lib/ui.js'))
  out.push(ui.indexOf('定期回収') >= 0 ? 'ui.js=最新版' : 'ui.js=古い版')
  return '\n  ' + out.join('\n  ')
}, 20000)

let model, store, sync, notify, ui
await step('モジュール読み込み', async () => {
  model = importModule('todo-lib/model')
  store = importModule('todo-lib/store')
  sync = importModule('todo-lib/sync')
  notify = importModule('todo-lib/notify')
  ui = importModule('todo-lib/ui')
  return 'OK'
})

let data
await step('データ読み込み', async () => {
  data = await store.load()
  return data.todos.length + '件'
})

await step('カレンダー一覧', async () => {
  const cals = await Calendar.forEvents()
  return cals.length + '個（' + cals.map(c => c.title).join('、') + '）'
})

await step('カレンダー同期', async () => {
  const r = await sync.syncCalendar(data, new Date(), model)
  return JSON.stringify(r)
}, 15000)

await step('通知予約', async () => {
  const n = await notify.reschedule(data, new Date(), model)
  return n + '件'
}, 15000)

await step('データ保存', async () => {
  store.save(data)
  return 'OK'
})

await step('最小のWebView表示', async () => {
  const wv = new WebView()
  await wv.loadHTML('<meta name="viewport" content="width=device-width"><h1 style="font-family:-apple-system">表示テストOK</h1><p>右上の「閉じる」で閉じてください</p>')
  await wv.present(true)
  return '閉じた'
}, 120000)

let html
await step('画面HTMLの生成', async () => {
  html = ui.buildHTML(data, model, null)
  return html.length + '文字'
})

await step('本番画面のWebView表示', async () => {
  const wv = new WebView()
  await wv.loadHTML(html)
  const info = await wv.evaluateJavaScript('(document.getElementById("app") || {}).innerHTML ? "描画あり" : "描画なし"')
  await wv.present(true)
  return info + '・閉じた'
}, 120000)

const report = results.join('\n')
console.log(report)
Pasteboard.copy(report)
await alert('診断結果（コピー済み）', report + '\n\n※この結果はクリップボードにコピーされています。チャットに貼り付けてください。')
Script.complete()
