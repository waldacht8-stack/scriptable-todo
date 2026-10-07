// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: green; icon-glyph: cloud-download-alt;
// TODO Update.js — GitHub から最新のプログラムを取得して Scriptable フォルダに上書きする（データは触らない）
const REPO = 'waldacht8-stack/scriptable-todo'
const BRANCH = 'main'

async function fetchText(url, json) {
  const r = new Request(url)
  r.headers = { 'User-Agent': 'scriptable-todo-updater', 'Accept': json ? 'application/vnd.github+json' : '*/*' }
  const body = await r.loadString()
  const code = r.response ? r.response.statusCode : 0
  if (code !== 200) throw new Error(url + ' → HTTP ' + code)
  return body
}

async function main() {
  // raw.githubusercontent.com はブランチ名だとキャッシュで古い版が返るので、最新コミットのSHAを指定して取る
  const commit = JSON.parse(await fetchText('https://api.github.com/repos/' + REPO + '/commits/' + BRANCH, true))
  const base = 'https://raw.githubusercontent.com/' + REPO + '/' + commit.sha + '/src/'
  const manifest = JSON.parse(await fetchText(base + 'manifest.json'))
  const fm = FileManager.iCloud()
  const dir = fm.documentsDirectory()
  const written = []
  for (const f of manifest.files) {
    const text = await fetchText(base + f.src.split('/').map(encodeURIComponent).join('/'))
    const dest = fm.joinPath(dir, f.dest)
    const parent = dest.substring(0, dest.lastIndexOf('/'))
    if (!fm.fileExists(parent)) fm.createDirectory(parent, true)
    fm.writeString(dest, text)
    written.push(f.dest)
  }
  // 配信をやめたスクリプトは削除する（データフォルダは対象外）
  const removed = []
  for (const name of manifest.remove || []) {
    if (name.indexOf('todo-data') === 0) continue
    const p = fm.joinPath(dir, name)
    if (fm.fileExists(p)) {
      fm.remove(p)
      removed.push(name)
    }
  }
  return '版: ' + commit.sha.slice(0, 7) + '\n' + (commit.commit.message || '').split('\n')[0] + '\n\n' + written.length + 'ファイルを更新しました' +
    (removed.length ? '\n不要なスクリプトを削除: ' + removed.join('、') : '')
}

const a = new Alert()
try {
  a.title = '更新完了'
  a.message = await main()
} catch (e) {
  a.title = '更新失敗'
  a.message = e && e.message ? e.message : String(e)
}
a.addAction('OK')
await a.presentAlert()
Script.complete()
