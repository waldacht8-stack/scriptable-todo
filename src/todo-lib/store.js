// todo-lib/store.js
// iCloud Drive の Scriptable/todo-data/todo-data.json に全データを保存する。

const DEFAULT_SETTINGS = {
  remindMinutes: 30,        // 期限の何分前に通知するか
  morningHour: 7,           // 朝の一覧通知の時刻
  morningMinute: 0,
  lookaheadDays: 14,        // 今日から何日先までカレンダーを取り込むか
  excludeCalendars: ['日本の祝日', '祝日', '誕生日', 'Birthdays', 'Japanese Holidays', 'Holidays in Japan'],
}

function files() {
  return FileManager.iCloud()
}

function dataDir() {
  const fm = files()
  const dir = fm.joinPath(fm.documentsDirectory(), 'todo-data')
  if (!fm.fileExists(dir)) fm.createDirectory(dir, true)
  return dir
}

function dataPath() {
  return files().joinPath(dataDir(), 'todo-data.json')
}

function normalize(raw) {
  const data = raw || {}
  return {
    version: 1,
    todos: Array.isArray(data.todos) ? data.todos : [],
    dismissed: data.dismissed && typeof data.dismissed === 'object' ? data.dismissed : {},
    settings: Object.assign({}, DEFAULT_SETTINGS, data.settings || {}),
    meta: Object.assign({ lastSync: null, lastErrorAt: null }, data.meta || {}),
  }
}

async function load() {
  const fm = files()
  const path = dataPath()
  if (!fm.fileExists(path)) return normalize(null)
  if (!fm.isFileDownloaded(path)) {
    // iCloud が止まっていると無期限に待つので、10秒で打ち切る
    await new Promise((resolve, reject) => {
      const t = new Timer()
      t.timeInterval = 10000
      t.schedule(() => reject(new Error('iCloud からデータを取得できません（10秒で打ち切り）')))
      fm.downloadFileFromiCloud(path).then(() => { t.invalidate(); resolve() }, e => { t.invalidate(); reject(e) })
    })
  }
  const text = fm.readString(path)
  try {
    return normalize(JSON.parse(text))
  } catch (e) {
    // 壊れたファイルは退避してから止める（上書きで消さない）
    fm.writeString(path + '.broken-' + Date.now(), text)
    throw new Error('データファイルが壊れています（退避済み）: ' + e.message)
  }
}

function save(data) {
  const fm = files()
  const path = dataPath()
  if (fm.fileExists(path)) {
    const backup = fm.joinPath(dataDir(), 'todo-data.backup.json')
    if (fm.fileExists(backup)) fm.remove(backup)
    fm.copy(path, backup)
  }
  fm.writeString(path, JSON.stringify(data, null, 1))
}

module.exports = { load, save, normalize, DEFAULT_SETTINGS }
