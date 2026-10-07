// todo-lib/store.js
// iCloud Drive の Scriptable/todo-data/todo-data.json に全データを保存する。

const DEFAULT_SETTINGS = {
  remindMinutes: 30,        // 期限の何分前に通知するか
  morningHour: 7,           // 朝の一覧通知の時刻
  morningMinute: 0,
  eveningHour: 20,          // 夜の残りタスク通知の時刻（null で送らない）
  eveningMinute: 0,
  lookaheadDays: 45,        // 今日から何日先までカレンダーを取り込むか（月表示のため約1か月半）
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

const DATA_VERSION = 2

function normalize(raw) {
  const data = raw || {}
  const settings = Object.assign({}, DEFAULT_SETTINGS, data.settings || {})
  // v1 → v2: 月表示のためにカレンダー取り込み範囲を 14日 → 45日 に広げる（保存済みの古い既定値を上書き）
  if ((data.version || 1) < 2 && settings.lookaheadDays < DEFAULT_SETTINGS.lookaheadDays) settings.lookaheadDays = DEFAULT_SETTINGS.lookaheadDays
  return {
    version: DATA_VERSION,
    todos: Array.isArray(data.todos) ? data.todos : [],
    dismissed: data.dismissed && typeof data.dismissed === 'object' ? data.dismissed : {},
    settings: settings,
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
