// tests/scriptable-mock.js
// Scriptable の実行環境を PC 上で再現するモック（docs.scriptable.app の API 仕様に合わせる）。
//   const env = createScriptableEnv({ ... })
//   await env.run('TODO.js')        … src/ のスクリプトを Scriptable と同じグローバルで実行
//   env.importModule('todo-lib/store') … モジュールを同じモック環境で読み込む
//   env.dispose()                   … 残っているタイマーを止める
// 方針：
//   - スクリプトは vm の別コンテキストで実行する（setTimeout / require などの Node 専用 API は見えない。Scriptable と同じ）
//   - モックのクラス・インスタンスは「存在しない API を読む/書く」と例外を投げる（綴り間違い・未対応 API の検出）
//   - プロパティに代入する値の型も確認する（例: textColor に Color 以外を入れたら例外）

const fs = require('fs')
const path = require('path')
const vm = require('vm')

const SRC = path.join(__dirname, '..', 'src')

class MockError extends Error {
  constructor(message) {
    super('[Scriptable モック] ' + message)
    this.name = 'MockError'
  }
}

// ---------- 厳密オブジェクト（存在しない API を検出する） ----------

// Node の表示処理や Promise 判定などが内部で読むプロパティは素通しにする
const PASS = new Set(['then', 'toJSON', 'constructor', 'inspect', 'nodeType', 'asymmetricMatch', '$$typeof', 'toString', 'valueOf', 'stack'])

function findDescriptor(obj, p) {
  for (let o = obj; o; o = Object.getPrototypeOf(o)) {
    const d = Object.getOwnPropertyDescriptor(o, p)
    if (d) return { d: d, own: o === obj }
  }
  return null
}

function tag(v) {
  return Object.prototype.toString.call(v).slice(8, -1)
}

// 型名 → 判定。末尾 '?' は null 可
function checkType(cls, prop, type, v) {
  const nullable = type.endsWith('?')
  const t = nullable ? type.slice(0, -1) : type
  if (v == null) {
    if (nullable) return
    throw new MockError(cls + '.' + prop + ' に ' + v + ' は代入できません（' + t + ' が必要）')
  }
  let ok
  if (t === 'string' || t === 'number' || t === 'boolean' || t === 'function') ok = typeof v === t && !(t === 'number' && !isFinite(v))
  else if (t === 'Date') ok = tag(v) === 'Date' && !isNaN(v.getTime())
  else if (t === 'any') ok = true
  else ok = !!v && v.__mockType === t
  if (!ok) throw new MockError(cls + '.' + prop + ' に不正な値（' + t + ' が必要）: ' + (typeof v === 'object' ? (v.__mockType || tag(v)) : JSON.stringify(v)))
}

function strict(target, cls, types) {
  const ty = types || {}
  return new Proxy(target, {
    get(t, p, r) {
      if (typeof p === 'symbol' || p in t || PASS.has(p)) return Reflect.get(t, p, r)
      throw new MockError(cls + '.' + p + ' は Scriptable に無い（またはモック未対応の）API です')
    },
    set(t, p, v) {
      if (typeof p === 'symbol') { t[p] = v; return true }
      const f = findDescriptor(t, p)
      if (!f || (!f.own && !f.d.set) || (f.d.get && !f.d.set) || (f.own && typeof f.d.value === 'function' && !(p in ty))) {
        throw new MockError(cls + '.' + p + ' は代入できるプロパティではありません')
      }
      if (ty[p]) checkType(cls, p, ty[p], v)
      if (f.d.set) f.d.set.call(t, v)
      else t[p] = v
      return true
    },
  })
}

// クラスの static 側も厳密にする
function strictClass(C, name) {
  return new Proxy(C, {
    get(t, p, r) {
      if (typeof p === 'symbol' || p in t || PASS.has(p)) return Reflect.get(t, p, r)
      throw new MockError(name + '.' + p + ' は Scriptable に無い（またはモック未対応の）API です')
    },
  })
}

function needArgs(name, args, types) {
  types.forEach((type, i) => checkType(name, '引数' + (i + 1), type, args[i]))
}

// ---------- 環境 ----------

function createScriptableEnv(opts) {
  const o = Object.assign({
    scriptName: 'TODO',
    runsInWidget: false,
    widgetFamily: null,
    shortcutParameter: null,
    queryParameters: {},
    widgetParameter: null,
    calendars: [{ title: '仕事' }, { title: '日本の祝日' }],
    events: [],                  // { identifier, title, startDate, endDate, isAllDay, calendar: 'カレンダー名' }
    calendarError: null,         // Error を入れると Calendar.forEvents が失敗する
    notificationError: null,     // Error を入れると Notification.schedule が失敗する
    iCloudAvailable: true,
    alertAnswers: [],            // Alert の応答（ボタン番号）を順に返す
    onWebViewPresent: null,      // async (page, env) => {} 画面表示中の操作。終わると画面が閉じる
    onTablePresent: null,        // async (table, env) => {}
    evaluateAfterClose: 'ok',    // 'ok' | 'hang' | 'reject'：画面を閉じた後の evaluateJavaScript の挙動
    echo: false,                 // true ならスクリプトの console 出力を表示
  }, opts || {})

  const env = {
    options: o,
    logs: [],              // { level, text }
    uncaught: [],          // タイマーのコールバック内で起きた例外など
    alerts: [],            // { title, message, actions, answer }
    notifications: { pending: new Map(), delivered: [], removed: [], scheduled: [] },
    script: { widget: null, output: undefined, completed: false, name: o.scriptName },
    webViews: [],
    tables: [],
    timers: new Set(),
    pages: [],
    savedEvents: [],       // new CalendarEvent().save() された予定
  }

  function log(level, args) {
    const text = args.map(a => (typeof a === 'string' ? a : (() => { try { return JSON.stringify(a) } catch (e) { return String(a) } })())).join(' ')
    env.logs.push({ level: level, text: text })
    if (o.echo) console.log('    [' + level + '] ' + text)
  }

  // ---------- ファイル（メモリ上） ----------
  const fsState = { files: new Map(), dirs: new Set(['/']) }
  const ROOTS = {
    iCloud: '/iCloud/Documents',
    local: '/local/Documents',
  }
  function addDir(p) {
    const parts = p.split('/').filter(Boolean)
    let cur = ''
    for (const x of parts) { cur += '/' + x; fsState.dirs.add(cur) }
  }
  Object.values(ROOTS).forEach(addDir)
  addDir('/local/Library'); addDir('/local/Caches'); addDir('/local/tmp'); addDir('/iCloud/Library')
  const parentOf = p => p.slice(0, p.lastIndexOf('/')) || '/'
  function norm(p, who) {
    if (typeof p !== 'string' || !p.startsWith('/')) throw new MockError(who + ': 絶対パスが必要です: ' + JSON.stringify(p))
    return p.replace(/\/+$/, '') || '/'
  }

  env.files = {
    write(p, text, extra) {
      addDir(parentOf(p))
      fsState.files.set(p, Object.assign({ text: String(text), mtime: new Date(), ctime: new Date(), downloaded: true }, extra || {}))
    },
    read(p) { const f = fsState.files.get(p); return f ? f.text : null },
    exists(p) { return fsState.files.has(p) || fsState.dirs.has(p) },
    list() { return Array.from(fsState.files.keys()).sort() },
    setDownloaded(p, v) { fsState.files.get(p).downloaded = v },
    roots: ROOTS,
  }

  class FileManager {
    constructor(kind) {
      this.__kind = kind
      this.__mockType = 'FileManager'
      return strict(this, 'FileManager')
    }
    static iCloud() {
      if (!o.iCloudAvailable) throw new Error('iCloud is not enabled on this device.')
      return new FileManager('iCloud')
    }
    static local() { return new FileManager('local') }
    documentsDirectory() { return ROOTS[this.__kind] }
    libraryDirectory() { return this.__kind === 'iCloud' ? '/iCloud/Library' : '/local/Library' }
    cacheDirectory() { return '/local/Caches' }
    temporaryDirectory() { return '/local/tmp' }
    joinPath(lhs, rhs) {
      needArgs('FileManager.joinPath', [lhs, rhs], ['string', 'string'])
      return lhs.replace(/\/+$/, '') + '/' + rhs.replace(/^\/+/, '')
    }
    fileExists(p) { p = norm(p, 'fileExists'); return fsState.files.has(p) || fsState.dirs.has(p) }
    isDirectory(p) { return fsState.dirs.has(norm(p, 'isDirectory')) }
    createDirectory(p, intermediate) {
      p = norm(p, 'createDirectory')
      if (fsState.dirs.has(p) || fsState.files.has(p)) throw new Error('createDirectory: 既に存在します: ' + p)
      if (!intermediate && !fsState.dirs.has(parentOf(p))) throw new Error('createDirectory: 親フォルダがありません: ' + p)
      addDir(p)
    }
    listContents(p) {
      p = norm(p, 'listContents')
      if (!fsState.dirs.has(p)) throw new Error('listContents: フォルダがありません: ' + p)
      const names = new Set()
      for (const k of fsState.files.keys()) if (parentOf(k) === p) names.add(k.slice(p.length + 1))
      for (const k of fsState.dirs) if (k !== p && parentOf(k) === p) names.add(k.slice(p.length + 1))
      return Array.from(names)
    }
    readString(p) {
      p = norm(p, 'readString')
      const f = fsState.files.get(p)
      if (!f) throw new Error('readString: ファイルがありません: ' + p)
      if (!f.downloaded) throw new Error('readString: iCloud から未ダウンロードのファイルです: ' + p)
      return f.text
    }
    writeString(p, content) {
      p = norm(p, 'writeString')
      needArgs('FileManager.writeString', [p, content], ['string', 'string'])
      if (!fsState.dirs.has(parentOf(p))) throw new Error('writeString: 親フォルダがありません: ' + p)
      if (fsState.dirs.has(p)) throw new Error('writeString: フォルダには書けません: ' + p)
      const old = fsState.files.get(p)
      fsState.files.set(p, { text: content, mtime: new Date(), ctime: old ? old.ctime : new Date(), downloaded: true })
    }
    copy(src, dst) {
      src = norm(src, 'copy'); dst = norm(dst, 'copy')
      const f = fsState.files.get(src)
      if (!f) throw new Error('copy: コピー元がありません: ' + src)
      if (fsState.files.has(dst) || fsState.dirs.has(dst)) throw new Error('copy: コピー先が既に存在します: ' + dst)
      if (!fsState.dirs.has(parentOf(dst))) throw new Error('copy: コピー先の親フォルダがありません: ' + dst)
      fsState.files.set(dst, Object.assign({}, f, { ctime: new Date() }))
    }
    move(src, dst) {
      this.copy(src, dst)
      fsState.files.delete(norm(src, 'move'))
    }
    remove(p) {
      p = norm(p, 'remove')
      if (fsState.files.delete(p)) return
      if (!fsState.dirs.has(p)) throw new Error('remove: ありません: ' + p)
      for (const k of Array.from(fsState.files.keys())) if (k.startsWith(p + '/')) fsState.files.delete(k)
      for (const k of Array.from(fsState.dirs)) if (k === p || k.startsWith(p + '/')) fsState.dirs.delete(k)
    }
    isFileStoredIniCloud(p) { return this.__kind === 'iCloud' && this.fileExists(p) }
    isFileDownloaded(p) {
      p = norm(p, 'isFileDownloaded')
      const f = fsState.files.get(p)
      return f ? f.downloaded : fsState.dirs.has(p)
    }
    downloadFileFromiCloud(p) {
      p = norm(p, 'downloadFileFromiCloud')
      const f = fsState.files.get(p)
      if (!f) return Promise.reject(new Error('downloadFileFromiCloud: ありません: ' + p))
      if (f.hangDownload) return new Promise(() => {})
      return Promise.resolve().then(() => { f.downloaded = true })
    }
    modificationDate(p) { const f = fsState.files.get(norm(p, 'modificationDate')); return f ? new Date(f.mtime) : null }
    creationDate(p) { const f = fsState.files.get(norm(p, 'creationDate')); return f ? new Date(f.ctime) : null }
    fileName(p, includeExt) {
      const n = p.slice(p.lastIndexOf('/') + 1)
      return includeExt || n.indexOf('.') < 0 ? n : n.slice(0, n.lastIndexOf('.'))
    }
    fileExtension(p) { const n = p.slice(p.lastIndexOf('/') + 1); return n.indexOf('.') < 0 ? '' : n.slice(n.lastIndexOf('.') + 1) }
  }

  // ---------- 色・フォント・図形 ----------
  class Color {
    constructor(hex, alpha) {
      needArgs('new Color', [hex], ['string'])
      if (!/^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(hex)) throw new MockError('new Color: 不正な16進カラー: ' + hex)
      if (alpha != null) needArgs('new Color(alpha)', [alpha], ['number'])
      this.hex = hex.replace('#', '').toUpperCase()
      this.alpha = alpha == null ? 1 : alpha
      this.red = 0; this.green = 0; this.blue = 0
      this.__light = null
      this.__dark = null
      this.__mockType = 'Color'
      return strict(this, 'Color')
    }
    static dynamic(light, dark) {
      needArgs('Color.dynamic', [light, dark], ['Color', 'Color'])
      const c = new Color(light.hex)
      c.__light = light
      c.__dark = dark
      return c
    }
    static black() { return new Color('#000000') }
    static white() { return new Color('#FFFFFF') }
    static clear() { return new Color('#000000', 0) }
    static red() { return new Color('#FF0000') }
    static blue() { return new Color('#0000FF') }
    static gray() { return new Color('#808080') }
    static orange() { return new Color('#FF8000') }
  }
  const fontKinds = ['systemFont', 'boldSystemFont', 'heavySystemFont', 'semiboldSystemFont', 'mediumSystemFont', 'lightSystemFont',
    'thinSystemFont', 'ultraLightSystemFont', 'blackSystemFont', 'italicSystemFont', 'regularMonospacedSystemFont',
    'boldMonospacedSystemFont', 'regularRoundedSystemFont', 'boldRoundedSystemFont']
  class Font {
    constructor(name, size) {
      needArgs('new Font', [name, size], ['string', 'number'])
      this.name = name
      this.size = size
      this.__mockType = 'Font'
      return strict(this, 'Font')
    }
  }
  for (const k of fontKinds) Font[k] = size => { needArgs('Font.' + k, [size], ['number']); return new Font(k, size) }
  for (const k of ['largeTitle', 'title1', 'title2', 'title3', 'headline', 'subheadline', 'body', 'callout', 'footnote', 'caption1', 'caption2']) Font[k] = () => new Font(k, 0)

  class Size {
    constructor(width, height) {
      needArgs('new Size', [width, height], ['number', 'number'])
      this.width = width; this.height = height; this.__mockType = 'Size'
      return strict(this, 'Size')
    }
  }
  class Point {
    constructor(x, y) {
      needArgs('new Point', [x, y], ['number', 'number'])
      this.x = x; this.y = y; this.__mockType = 'Point'
      return strict(this, 'Point')
    }
  }
  class Rect {
    constructor(x, y, width, height) {
      needArgs('new Rect', [x, y, width, height], ['number', 'number', 'number', 'number'])
      this.x = x; this.y = y; this.width = width; this.height = height
      this.minX = x; this.minY = y; this.maxX = x + width; this.maxY = y + height
      this.origin = new Point(x, y); this.size = new Size(width, height)
      this.__mockType = 'Rect'
      return strict(this, 'Rect')
    }
  }
  class Image {
    constructor(desc, size) {
      this.size = size || new Size(1, 1)
      this.__desc = desc
      this.__mockType = 'Image'
      return strict(this, 'Image')
    }
    static fromFile() { throw new MockError('Image.fromFile はモック未対応') }
    static fromData() { throw new MockError('Image.fromData はモック未対応') }
  }
  class SFSymbol {
    constructor(name) {
      this.__name = name
      this.image = new Image('sf:' + name, new Size(20, 20))
      this.__mockType = 'SFSymbol'
      return strict(this, 'SFSymbol')
    }
    static named(name) {
      needArgs('SFSymbol.named', [name], ['string'])
      return name ? new SFSymbol(name) : null
    }
    applyFont(f) { needArgs('SFSymbol.applyFont', [f], ['Font']) }
    applyThinWeight() {} applyLightWeight() {} applyRegularWeight() {} applyMediumWeight() {}
    applySemiboldWeight() {} applyBoldWeight() {} applyHeavyWeight() {} applyBlackWeight() {}
  }
  class Path {
    constructor() {
      this.__ops = []
      this.__mockType = 'Path'
      return strict(this, 'Path')
    }
    move(p) { needArgs('Path.move', [p], ['Point']); this.__ops.push('move') }
    addLine(p) { needArgs('Path.addLine', [p], ['Point']); this.__ops.push('line') }
    addRect(r) { needArgs('Path.addRect', [r], ['Rect']); this.__ops.push('rect') }
    addEllipse(r) { needArgs('Path.addEllipse', [r], ['Rect']); this.__ops.push('ellipse') }
    addRoundedRect(r, cw, ch) { needArgs('Path.addRoundedRect', [r, cw, ch], ['Rect', 'number', 'number']); this.__ops.push('rrect') }
    addCurve(p, c1, c2) { needArgs('Path.addCurve', [p, c1, c2], ['Point', 'Point', 'Point']) }
    addQuadCurve(p, c) { needArgs('Path.addQuadCurve', [p, c], ['Point', 'Point']) }
    addLines(ps) {} addRects(rs) {}
    closeSubpath() {}
  }
  class DrawContext {
    constructor() {
      this.size = new Size(200, 200)
      this.respectScreenScale = false
      this.opaque = true
      this.__path = null
      this.__ops = []
      this.__mockType = 'DrawContext'
      return strict(this, 'DrawContext', { size: 'Size', respectScreenScale: 'boolean', opaque: 'boolean' })
    }
    getImage() { return new Image('draw:' + this.__ops.join(','), this.size) }
    addPath(p) { needArgs('DrawContext.addPath', [p], ['Path']); this.__path = p }
    fillPath() { if (!this.__path) throw new MockError('fillPath: addPath されていません'); this.__ops.push('fillPath') }
    strokePath() { if (!this.__path) throw new MockError('strokePath: addPath されていません'); this.__ops.push('strokePath') }
    setFillColor(c) { needArgs('DrawContext.setFillColor', [c], ['Color']) }
    setStrokeColor(c) { needArgs('DrawContext.setStrokeColor', [c], ['Color']) }
    setLineWidth(w) { needArgs('DrawContext.setLineWidth', [w], ['number']) }
    setTextColor(c) { needArgs('DrawContext.setTextColor', [c], ['Color']) }
    setFont(f) { needArgs('DrawContext.setFont', [f], ['Font']) }
    setTextAlignedLeft() {} setTextAlignedCenter() {} setTextAlignedRight() {}
    fillRect(r) { needArgs('DrawContext.fillRect', [r], ['Rect']) }
    strokeRect(r) { needArgs('DrawContext.strokeRect', [r], ['Rect']) }
    fillEllipse(r) { needArgs('DrawContext.fillEllipse', [r], ['Rect']) }
    strokeEllipse(r) { needArgs('DrawContext.strokeEllipse', [r], ['Rect']) }
    drawText(t, p) { needArgs('DrawContext.drawText', [t, p], ['string', 'Point']) }
    drawTextInRect(t, r) { needArgs('DrawContext.drawTextInRect', [t, r], ['string', 'Rect']) }
    drawImageInRect(i, r) { needArgs('DrawContext.drawImageInRect', [i, r], ['Image', 'Rect']) }
    drawImageAtPoint(i, p) { needArgs('DrawContext.drawImageAtPoint', [i, p], ['Image', 'Point']) }
  }

  // ---------- ウィジェット（木構造を記録する） ----------
  const containerTypes = {
    backgroundColor: 'Color', backgroundImage: 'Image', backgroundGradient: 'any', spacing: 'number', url: 'string',
  }
  class WidgetBase {
    __add(child) { this.children.push(child); return child }
    addText(text) {
      needArgs(this.__mockType + '.addText', [text], ['string'])
      return this.__add(new WidgetText(text))
    }
    addDate(date) { needArgs(this.__mockType + '.addDate', [date], ['Date']); return this.__add(new WidgetDate(date)) }
    addImage(image) { needArgs(this.__mockType + '.addImage', [image], ['Image']); return this.__add(new WidgetImage(image)) }
    addSpacer(length) {
      if (length != null) needArgs(this.__mockType + '.addSpacer', [length], ['number'])
      return this.__add(new WidgetSpacer(length == null ? null : length))
    }
    addStack() { return this.__add(new WidgetStack()) }
    setPadding(top, leading, bottom, trailing) {
      needArgs(this.__mockType + '.setPadding', [top, leading, bottom, trailing], ['number', 'number', 'number', 'number'])
      this.__padding = [top, leading, bottom, trailing]
    }
    useDefaultPadding() { this.__padding = null }
  }
  class ListWidget extends WidgetBase {
    constructor() {
      super()
      this.children = []
      this.backgroundColor = null
      this.backgroundImage = null
      this.backgroundGradient = null
      this.addAccessoryWidgetBackground = false
      this.spacing = 0
      this.url = null
      this.refreshAfterDate = null
      this.__padding = null
      this.__mockType = 'ListWidget'
      return strict(this, 'ListWidget', Object.assign({ addAccessoryWidgetBackground: 'boolean', refreshAfterDate: 'Date' }, containerTypes))
    }
    presentSmall() { return Promise.resolve() }
    presentMedium() { return Promise.resolve() }
    presentLarge() { return Promise.resolve() }
    presentExtraLarge() { return Promise.resolve() }
    presentAccessoryInline() { return Promise.resolve() }
    presentAccessoryCircular() { return Promise.resolve() }
    presentAccessoryRectangular() { return Promise.resolve() }
  }
  class WidgetStack extends WidgetBase {
    constructor() {
      super()
      this.children = []
      this.backgroundColor = null
      this.backgroundImage = null
      this.backgroundGradient = null
      this.spacing = 0
      this.size = null
      this.cornerRadius = 0
      this.borderWidth = 0
      this.borderColor = null
      this.url = null
      this.__layout = 'horizontal' // 既定は横並び
      this.__align = null
      this.__padding = null
      this.__mockType = 'WidgetStack'
      return strict(this, 'WidgetStack', Object.assign({ size: 'Size', cornerRadius: 'number', borderWidth: 'number', borderColor: 'Color' }, containerTypes))
    }
    layoutHorizontally() { this.__layout = 'horizontal' }
    layoutVertically() { this.__layout = 'vertical' }
    topAlignContent() { this.__align = 'top' }
    centerAlignContent() { this.__align = 'center' }
    bottomAlignContent() { this.__align = 'bottom' }
  }
  class WidgetText {
    constructor(text) {
      this.text = text
      this.textColor = null
      this.font = null
      this.textOpacity = 1
      this.lineLimit = 0
      this.minimumScaleFactor = 1
      this.shadowColor = null
      this.shadowRadius = 0
      this.shadowOffset = null
      this.url = null
      this.__align = null
      this.__mockType = 'WidgetText'
      return strict(this, 'WidgetText', {
        text: 'string', textColor: 'Color', font: 'Font', textOpacity: 'number', lineLimit: 'number', minimumScaleFactor: 'number',
        shadowColor: 'Color', shadowRadius: 'number', shadowOffset: 'Point', url: 'string',
      })
    }
    leftAlignText() { this.__align = 'left' }
    centerAlignText() { this.__align = 'center' }
    rightAlignText() { this.__align = 'right' }
  }
  class WidgetDate {
    constructor(date) {
      this.date = date
      this.textColor = null
      this.font = null
      this.lineLimit = 0
      this.minimumScaleFactor = 1
      this.url = null
      this.__mockType = 'WidgetDate'
      return strict(this, 'WidgetDate', { date: 'Date', textColor: 'Color', font: 'Font', lineLimit: 'number', minimumScaleFactor: 'number', url: 'string' })
    }
    applyTimeStyle() {} applyDateStyle() {} applyRelativeStyle() {} applyOffsetStyle() {} applyTimerStyle() {}
    leftAlignText() {} centerAlignText() {} rightAlignText() {}
  }
  class WidgetImage {
    constructor(image) {
      this.image = image
      this.resizable = true
      this.imageSize = null
      this.imageOpacity = 1
      this.cornerRadius = 0
      this.borderWidth = 0
      this.borderColor = null
      this.containerRelativeShape = false
      this.tintColor = null
      this.url = null
      this.__mockType = 'WidgetImage'
      return strict(this, 'WidgetImage', {
        image: 'Image', resizable: 'boolean', imageSize: 'Size', imageOpacity: 'number', cornerRadius: 'number', borderWidth: 'number',
        borderColor: 'Color', containerRelativeShape: 'boolean', tintColor: 'Color', url: 'string',
      })
    }
    leftAlignImage() {} centerAlignImage() {} rightAlignImage() {}
    applyFittingContentMode() {} applyFillingContentMode() {}
  }
  class WidgetSpacer {
    constructor(length) {
      this.length = length
      this.__mockType = 'WidgetSpacer'
      return strict(this, 'WidgetSpacer', { length: 'number?' })
    }
  }

  // ウィジェットの木を簡単な文字列にする（テストの確認用）
  env.widgetTexts = w => {
    const out = []
    const walk = n => {
      if (n.__mockType === 'WidgetText') out.push(n.text)
      if (n.__mockType === 'ListWidget' || n.__mockType === 'WidgetStack') n.children.forEach(walk)
    }
    walk(w)
    return out
  }
  env.widgetTree = w => {
    const walk = (n, depth) => {
      const pad = '  '.repeat(depth)
      if (n.__mockType === 'WidgetText') return pad + 'Text ' + JSON.stringify(n.text)
      if (n.__mockType === 'WidgetImage') return pad + 'Image'
      if (n.__mockType === 'WidgetSpacer') return pad + 'Spacer' + (n.length != null ? ' ' + n.length : '')
      if (n.__mockType === 'WidgetDate') return pad + 'Date ' + n.date.toISOString()
      const head = pad + n.__mockType + (n.__mockType === 'WidgetStack' ? ' ' + n.__layout : '')
      return [head].concat(n.children.map(c => walk(c, depth + 1))).join('\n')
    }
    return walk(w, 0)
  }

  // ---------- カレンダー ----------
  const calendarObjs = o.calendars.map((c, i) => strict({
    identifier: c.identifier || 'cal-' + i, title: c.title, isSubscribed: !!c.isSubscribed,
    allowsContentModifications: true, color: new Color('#1D4ED8'), __mockType: 'Calendar',
  }, 'Calendar'))
  function eventObj(e) {
    const cal = calendarObjs.find(c => c.title === e.calendar) || calendarObjs[0]
    return strict({
      identifier: e.identifier, title: e.title, notes: e.notes || null, location: e.location || null,
      startDate: new Date(e.startDate), endDate: new Date(e.endDate || e.startDate),
      isAllDay: !!e.isAllDay, calendar: cal, attendees: null, availability: 'busy', timeZone: 'Asia/Tokyo',
      __mockType: 'CalendarEvent',
    }, 'CalendarEvent')
  }
  const Calendar = {
    forEvents() {
      if (o.calendarError) return Promise.reject(o.calendarError)
      return Promise.resolve(calendarObjs.slice())
    },
    forReminders() { return Promise.resolve([]) },
    defaultForEvents() { return Promise.resolve(calendarObjs[0]) },
    forEventsByTitle(title) {
      const c = calendarObjs.find(x => x.title === title)
      return c ? Promise.resolve(c) : Promise.reject(new Error('No calendar named ' + title))
    },
  }
  // new CalendarEvent() → save() で o.events に追加される（Scriptable と同様、identifier は save 後に付く）
  let eventSeq = 0
  function CalendarEvent() {
    const ev = {
      identifier: null, title: '', notes: null, location: null, url: null,
      startDate: null, endDate: null, isAllDay: false,
      get calendar() { return calendarObjs[0] }, // ドキュメント上 read-only（代入は例外）
      attendees: null, availability: 'busy', timeZone: 'Asia/Tokyo', __mockType: 'CalendarEvent',
      save() {
        if (typeof ev.title !== 'string' || !ev.title) return Promise.reject(new MockError('CalendarEvent.save: title が空'))
        needArgs('CalendarEvent.save', [ev.startDate, ev.endDate], ['Date', 'Date'])
        if (ev.endDate < ev.startDate) return Promise.reject(new MockError('CalendarEvent.save: endDate が startDate より前'))
        const cal = ev.calendar || calendarObjs[0]
        if (!ev.identifier) ev.identifier = 'created-' + (++eventSeq)
        const rec = { identifier: ev.identifier, title: ev.title, notes: ev.notes, startDate: ev.startDate, endDate: ev.endDate, isAllDay: !!ev.isAllDay, calendar: cal.title }
        const i = o.events.findIndex(e => e.identifier === rec.identifier)
        if (i >= 0) o.events[i] = rec
        else o.events.push(rec)
        env.savedEvents.push(rec)
        return Promise.resolve()
      },
      remove() {
        const i = o.events.findIndex(e => e.identifier === ev.identifier)
        if (i >= 0) o.events.splice(i, 1)
      },
    }
    return strict(ev, 'CalendarEvent', { startDate: 'Date', endDate: 'Date' })
  }
  CalendarEvent.between = function (start, end, calendars) {
      needArgs('CalendarEvent.between', [start, end], ['Date', 'Date'])
      if (calendars != null && !Array.isArray(calendars)) throw new MockError('CalendarEvent.between: calendars は配列')
      if (o.calendarError) return Promise.reject(o.calendarError)
      const titles = calendars && calendars.length ? calendars.map(c => c.title) : null // 空配列は全カレンダー
      const list = o.events
        .map(eventObj)
        .filter(ev => ev.startDate < end && ev.endDate > start || (ev.startDate >= start && ev.startDate < end))
        .filter(ev => !titles || titles.indexOf(ev.calendar.title) >= 0)
      return Promise.resolve(list)
  }
  CalendarEvent.today = function (calendars) { return CalendarEvent.between(startOfToday(), new Date(startOfToday().getTime() + 86400e3), calendars) }
  function startOfToday() { const d = new Date(); d.setHours(0, 0, 0, 0); return d }

  // ---------- 通知 ----------
  class Notification {
    constructor() {
      this.identifier = 'auto-' + Math.random().toString(36).slice(2)
      this.title = ''
      this.subtitle = ''
      this.body = ''
      this.preferredContentHeight = null
      this.badge = null
      this.threadIdentifier = ''
      this.userInfo = {}
      this.sound = null
      this.openURL = null
      this.deliveryDate = null
      this.nextTriggerDate = null
      this.scriptName = o.scriptName
      this.actions = []
      this.__daily = null
      this.__weekly = null
      this.__mockType = 'Notification'
      return strict(this, 'Notification', {
        identifier: 'string', title: 'string', subtitle: 'string', body: 'string', threadIdentifier: 'string',
        openURL: 'string?', sound: 'string?', badge: 'number?', preferredContentHeight: 'number?', userInfo: 'any',
      })
    }
    setTriggerDate(date) {
      needArgs('Notification.setTriggerDate', [date], ['Date'])
      this.nextTriggerDate = new Date(date)
    }
    setDailyTrigger(hour, minute, repeats) { needArgs('Notification.setDailyTrigger', [hour, minute], ['number', 'number']); this.__daily = [hour, minute, !!repeats] }
    setWeeklyTrigger(weekday, hour, minute, repeats) { this.__weekly = [weekday, hour, minute, !!repeats] }
    addAction(title, url, destructive) { needArgs('Notification.addAction', [title, url], ['string', 'string']); this.actions.push({ title, url, destructive: !!destructive }) }
    schedule() {
      if (o.notificationError) return Promise.reject(o.notificationError)
      const rec = {
        identifier: this.identifier, title: this.title, body: this.body, threadIdentifier: this.threadIdentifier,
        openURL: this.openURL, triggerDate: this.nextTriggerDate ? new Date(this.nextTriggerDate) : null,
        actions: this.actions.slice(),
      }
      env.notifications.scheduled.push(rec)
      env.notifications.pending.delete(rec.identifier) // 同じ identifier は置き換え
      if (rec.triggerDate && rec.triggerDate > new Date()) env.notifications.pending.set(rec.identifier, rec)
      else env.notifications.delivered.push(rec) // トリガー無し（または過去）はすぐ配信される
      return Promise.resolve()
    }
    remove() { env.notifications.pending.delete(this.identifier); return Promise.resolve() }
    static allPending() {
      return Promise.resolve(Array.from(env.notifications.pending.values()).map(rec => {
        const n = new Notification()
        n.identifier = rec.identifier
        n.title = rec.title || ''
        n.body = rec.body || ''
        n.nextTriggerDate = rec.triggerDate
        return n
      }))
    }
    static allDelivered() { return Promise.resolve([]) }
    static removePending(ids) {
      if (!Array.isArray(ids)) throw new MockError('Notification.removePending: 識別子の配列が必要')
      for (const id of ids) { env.notifications.pending.delete(id); env.notifications.removed.push(id) }
      return Promise.resolve()
    }
    static removeDelivered(ids) { return Promise.resolve() }
    static removeAllPending() { env.notifications.pending.clear(); return Promise.resolve() }
    static removeAllDelivered() { return Promise.resolve() }
    static resetCurrent() { return Promise.resolve() }
  }

  // ---------- タイマー（本物の setTimeout を使う） ----------
  class Timer {
    constructor() {
      this.timeInterval = 0
      this.repeats = false
      this.__h = null
      this.__mockType = 'Timer'
      return strict(this, 'Timer', { timeInterval: 'number', repeats: 'boolean' })
    }
    schedule(callback) {
      needArgs('Timer.schedule', [callback], ['function'])
      if (this.__h) throw new MockError('Timer.schedule: 同じタイマーを二重に schedule しています')
      const self = this
      const fire = () => {
        if (!self.repeats) { self.__h = null; env.timers.delete(self) }
        try {
          callback(self)
        } catch (e) {
          env.uncaught.push(e)
        }
      }
      this.__h = this.repeats ? setInterval(fire, Math.max(1, this.timeInterval)) : setTimeout(fire, this.timeInterval)
      env.timers.add(self)
    }
    invalidate() {
      if (this.__h) { clearTimeout(this.__h); clearInterval(this.__h) }
      this.__h = null
      env.timers.delete(this)
    }
    static schedule(timeInterval, repeats, callback) {
      needArgs('Timer.schedule', [timeInterval, repeats, callback], ['number', 'boolean', 'function'])
      const t = new Timer()
      t.timeInterval = timeInterval
      t.repeats = repeats
      t.schedule(callback)
      return t
    }
  }

  // ---------- Alert ----------
  const answers = o.alertAnswers.slice()
  class Alert {
    constructor() {
      this.title = ''
      this.message = ''
      this.__actions = []
      this.__fields = []
      this.__cancel = null
      this.__mockType = 'Alert'
      return strict(this, 'Alert', { title: 'string', message: 'string' })
    }
    addAction(title) { needArgs('Alert.addAction', [title], ['string']); this.__actions.push(title) }
    addDestructiveAction(title) { needArgs('Alert.addDestructiveAction', [title], ['string']); this.__actions.push(title) }
    addCancelAction(title) { needArgs('Alert.addCancelAction', [title], ['string']); this.__cancel = title }
    addTextField(placeholder, text) { this.__fields.push(text == null ? '' : String(text)) }
    addSecureTextField(placeholder, text) { this.__fields.push(text == null ? '' : String(text)) }
    textFieldValue(index) {
      if (index < 0 || index >= this.__fields.length) throw new MockError('Alert.textFieldValue: 範囲外 ' + index)
      return this.__fields[index]
    }
    __answer() {
      if (!this.__actions.length && this.__cancel == null) throw new MockError('Alert: ボタンが1つもありません')
      const a = answers.length ? answers.shift() : (this.__actions.length ? 0 : -1)
      const index = typeof a === 'object' ? a.index : a
      if (a && typeof a === 'object' && a.fields) this.__fields = a.fields.slice()
      env.alerts.push({ title: this.title, message: this.message, actions: this.__actions.slice(), answer: index })
      return Promise.resolve(index)
    }
    present() { return this.__answer() }
    presentAlert() { return this.__answer() }
    presentSheet() { return this.__answer() }
  }

  // ---------- WebView と疑似ブラウザ ----------
  class WebView {
    constructor() {
      this.shouldAllowRequest = null
      this.__page = null
      this.__presented = false
      this.__closed = false
      this.__mockType = 'WebView'
      env.webViews.push(this)
      return strict(this, 'WebView', { shouldAllowRequest: 'function?' })
    }
    loadHTML(html, baseURL, preferredSize) {
      needArgs('WebView.loadHTML', [html], ['string'])
      if (this.__page) this.__page.dispose()
      this.__page = new FakePage(html, this, env)
      return Promise.resolve()
    }
    loadURL(url) { throw new MockError('WebView.loadURL はモック未対応') }
    loadFile(p) { throw new MockError('WebView.loadFile はモック未対応') }
    waitForLoad() { return Promise.resolve() }
    getHTML() { return Promise.resolve(this.__page ? this.__page.outerHTML() : '') }
    evaluateJavaScript(js, useCallback) {
      needArgs('WebView.evaluateJavaScript', [js], ['string'])
      if (this.__closed && o.evaluateAfterClose === 'hang') return new Promise(() => {})
      if (this.__closed && o.evaluateAfterClose === 'reject') return Promise.reject(new Error('WebView は破棄されています'))
      if (!this.__page) return Promise.reject(new Error('evaluateJavaScript: ページが読み込まれていません'))
      return this.__page.evaluate(js, !!useCallback)
    }
    async present(fullscreen) {
      if (this.__presented) throw new MockError('WebView.present: 既に表示中です')
      this.__presented = true
      if (o.onWebViewPresent) await o.onWebViewPresent(this.__page, env, this)
      this.__presented = false
      this.__closed = true
    }
  }

  // ---------- UITable ----------
  class UITableCell {
    constructor(kind, title, subtitle) {
      this.__kind = kind
      this.title = title == null ? null : title
      this.subtitle = subtitle == null ? null : subtitle
      this.widthWeight = 1
      this.onTap = null
      this.dismissOnTap = false
      this.titleColor = null
      this.subtitleColor = null
      this.titleFont = null
      this.subtitleFont = null
      this.__align = 'left'
      this.__mockType = 'UITableCell'
      return strict(this, 'UITableCell', {
        widthWeight: 'number', onTap: 'function?', dismissOnTap: 'boolean', titleColor: 'Color', subtitleColor: 'Color',
        titleFont: 'Font', subtitleFont: 'Font',
      })
    }
    static empty() { return new UITableCell('empty') }
    static text(title, subtitle) { return new UITableCell('text', title, subtitle) }
    static button(title) { return new UITableCell('button', title) }
    static image(image) { return new UITableCell('image') }
    static imageAtURL(url) { return new UITableCell('image') }
    leftAligned() { this.__align = 'left' }
    centerAligned() { this.__align = 'center' }
    rightAligned() { this.__align = 'right' }
  }
  class UITableRow {
    constructor() {
      this.cells = []
      this.cellSpacing = 0
      this.height = 44
      this.isHeader = false
      this.dismissOnSelect = true
      this.onSelect = null
      this.backgroundColor = null
      this.__mockType = 'UITableRow'
      return strict(this, 'UITableRow', {
        cellSpacing: 'number', height: 'number', isHeader: 'boolean', dismissOnSelect: 'boolean', onSelect: 'function?', backgroundColor: 'Color',
      })
    }
    addCell(cell) { needArgs('UITableRow.addCell', [cell], ['UITableCell']); this.cells.push(cell) }
    addText(title, subtitle) { const c = UITableCell.text(title, subtitle); this.cells.push(c); return c }
    addButton(title) { const c = UITableCell.button(title); this.cells.push(c); return c }
    addImage(image) { const c = UITableCell.image(image); this.cells.push(c); return c }
    addImageAtURL(url) { const c = UITableCell.imageAtURL(url); this.cells.push(c); return c }
  }
  class UITable {
    constructor() {
      this.rows = []
      this.showSeparators = false
      this.__mockType = 'UITable'
      env.tables.push(this)
      return strict(this, 'UITable', { showSeparators: 'boolean' })
    }
    addRow(row) { needArgs('UITable.addRow', [row], ['UITableRow']); this.rows.push(row) }
    removeRow(row) { this.rows = this.rows.filter(r => r !== row) }
    removeAllRows() { this.rows = [] }
    reload() {}
    async present(fullscreen) {
      if (o.onTablePresent) await o.onTablePresent(this, env)
    }
  }
  class DatePicker {
    constructor() {
      this.initialDate = new Date()
      this.minimumDate = null
      this.maximumDate = null
      this.countdownDuration = 0
      this.minuteInterval = 1
      this.__mockType = 'DatePicker'
      return strict(this, 'DatePicker', { initialDate: 'Date', minimumDate: 'Date?', maximumDate: 'Date?' })
    }
    pickTime() { return Promise.resolve(new Date(this.initialDate)) }
    pickDate() { return Promise.resolve(new Date(this.initialDate)) }
    pickDateAndTime() { return Promise.resolve(new Date(this.initialDate)) }
    pickCountdownDuration() { return Promise.resolve(60) }
  }

  // ---------- Script / URLScheme / config / args ----------
  const Script = {
    name() { return o.scriptName },
    complete() { env.script.completed = true },
    setShortcutOutput(value) { env.script.output = value },
    setWidget(widget) {
      if (!widget || widget.__mockType !== 'ListWidget') throw new MockError('Script.setWidget: ListWidget が必要です')
      env.script.widget = widget
    },
  }
  const URLScheme = {
    forRunningScript() { return 'scriptable:///run/' + encodeURIComponent(o.scriptName) },
    forOpeningScript() { return 'scriptable:///open/' + encodeURIComponent(o.scriptName) },
    forOpeningScriptSettings() { return 'scriptable:///settings/' + encodeURIComponent(o.scriptName) },
    allParameters() { return Object.assign({}, o.queryParameters) },
    parameter(name) { return o.queryParameters[name] == null ? null : o.queryParameters[name] },
  }
  const config = strict({
    runsInApp: !o.runsInWidget && !o.runsWithSiri && o.shortcutParameter == null,
    runsInActionExtension: false,
    runsWithSiri: !!o.runsWithSiri,
    runsInWidget: !!o.runsInWidget,
    runsInAccessoryWidget: !!(o.runsInWidget && o.widgetFamily && o.widgetFamily.indexOf('accessory') === 0),
    runsInNotification: false,
    runsFromHomeScreen: false,
    widgetFamily: o.runsInWidget ? o.widgetFamily : null,
  }, 'config')
  const args = strict({
    plainTexts: [], urls: [], fileURLs: [], images: [],
    queryParameters: Object.assign({}, o.queryParameters),
    shortcutParameter: o.shortcutParameter,
    widgetParameter: o.widgetParameter,
    notification: null,
    length: 0,
    all: [],
  }, 'args')

  const scriptConsole = {
    log: (...a) => log('log', a),
    warn: (...a) => log('warn', a),
    error: (...a) => log('error', a),
    logError: (...a) => log('error', a),
  }

  // ---------- 実行コンテキスト ----------
  const globals = {
    console: scriptConsole,
    FileManager: strictClass(FileManager, 'FileManager'),
    Color: strictClass(Color, 'Color'),
    Font: strictClass(Font, 'Font'),
    Size: strictClass(Size, 'Size'),
    Point: strictClass(Point, 'Point'),
    Rect: strictClass(Rect, 'Rect'),
    Image: strictClass(Image, 'Image'),
    SFSymbol: strictClass(SFSymbol, 'SFSymbol'),
    Path: strictClass(Path, 'Path'),
    DrawContext: strictClass(DrawContext, 'DrawContext'),
    ListWidget: strictClass(ListWidget, 'ListWidget'),
    WidgetStack: strictClass(WidgetStack, 'WidgetStack'),
    WidgetText: strictClass(WidgetText, 'WidgetText'),
    WidgetImage: strictClass(WidgetImage, 'WidgetImage'),
    WidgetSpacer: strictClass(WidgetSpacer, 'WidgetSpacer'),
    WidgetDate: strictClass(WidgetDate, 'WidgetDate'),
    Calendar: strict(Calendar, 'Calendar'),
    CalendarEvent: strictClass(CalendarEvent, 'CalendarEvent'),
    Notification: strictClass(Notification, 'Notification'),
    Timer: strictClass(Timer, 'Timer'),
    Alert: strictClass(Alert, 'Alert'),
    WebView: strictClass(WebView, 'WebView'),
    UITable: strictClass(UITable, 'UITable'),
    UITableRow: strictClass(UITableRow, 'UITableRow'),
    UITableCell: strictClass(UITableCell, 'UITableCell'),
    DatePicker: strictClass(DatePicker, 'DatePicker'),
    Script: strict(Script, 'Script'),
    URLScheme: strict(URLScheme, 'URLScheme'),
    config: config,
    args: args,
  }
  const context = vm.createContext(Object.assign({}, globals))
  env.globals = globals
  env.context = context

  // importModule：呼び出し元ファイルのフォルダ基準で解決し、同じモック環境で評価する
  const moduleCache = new Map()
  function makeImport(baseDir) {
    return function importModule(name) {
      needArgs('importModule', [name], ['string'])
      let file = path.resolve(baseDir, name)
      if (!/\.js$/.test(file)) file += '.js'
      if (moduleCache.has(file)) return moduleCache.get(file).exports
      if (!fs.existsSync(file)) throw new Error('importModule: モジュールが見つかりません: ' + name)
      const code = fs.readFileSync(file, 'utf8')
      const fn = vm.runInContext('(function (module, exports, importModule) {' + code + '\n})', context, { filename: file })
      const module = { exports: {} }
      moduleCache.set(file, module)
      fn(module, module.exports, makeImport(path.dirname(file)))
      return module.exports
    }
  }
  context.importModule = makeImport(SRC)
  env.importModule = context.importModule

  // スクリプトを Scriptable と同様に実行する（トップレベル await 可）
  env.run = function (rel) {
    const file = path.join(SRC, rel)
    const code = fs.readFileSync(file, 'utf8')
    const fn = vm.runInContext('(async function (importModule) {' + code + '\n})', context, { filename: file })
    return fn(makeImport(path.dirname(file)))
  }

  env.dispose = function () {
    for (const t of Array.from(env.timers)) t.invalidate()
    for (const p of env.pages) p.dispose()
  }

  env.errors = () => env.logs.filter(l => l.level === 'error').map(l => l.text)

  env.wait = ms => new Promise(r => setTimeout(r, ms))
  // 条件が満たされるまで待つ（最大 ms）
  env.waitFor = async (cond, ms, label) => {
    const end = Date.now() + (ms || 3000)
    while (Date.now() < end) {
      if (cond()) return
      await env.wait(20)
    }
    throw new Error('待機タイムアウト: ' + (label || ''))
  }

  return env
}

// ---------- 疑似ブラウザ（WebView の中身） ----------
// ページ内の <script> を別の vm コンテキストで実行する。DOM は ui.js が使う範囲だけの簡易版：
// getElementById / innerHTML / value / classList / getAttribute / closest('[attr]') / addEventListener('click')

function decodeEntities(s) {
  return String(s).replace(/&(amp|lt|gt|quot|#39);/g, (m, e) => ({ amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" }[e]))
}

function parseAttrs(s) {
  const attrs = {}
  const re = /([\w:-]+)(?:="([^"]*)")?/g
  let m
  while ((m = re.exec(s))) attrs[m[1]] = m[2] == null ? '' : decodeEntities(m[2])
  return attrs
}

// HTML 中のタグを { tag, attrs, inner } の一覧にする（入れ子の対応は textarea の中身のためだけ）
function scanTags(html) {
  const out = []
  const re = /<([a-zA-Z][\w-]*)(\s[^>]*)?>/g
  let m
  while ((m = re.exec(html))) {
    const t = { tag: m[1].toLowerCase(), attrs: parseAttrs(m[2] || '') }
    if (t.tag === 'textarea') {
      const end = html.indexOf('</textarea>', re.lastIndex)
      t.inner = decodeEntities(html.slice(re.lastIndex, end))
    }
    out.push(t)
  }
  return out
}

class FakePage {
  constructor(html, wv, env) {
    this.html = html
    this.wv = wv
    this.env = env
    this.errors = []
    this.logs = []
    this.navigations = []
    this.listeners = { click: [] }
    this.handles = new Set()
    this.elements = new Map()
    this.disposed = false
    env.pages.push(this)
    const page = this

    // --- DOM ---
    this.makeElement = (t, owner) => {
      const el = {
        tagName: t.tag.toUpperCase(),
        id: t.attrs.id || '',
        __attrs: t.attrs,
        __html: '',
        __owner: owner || null,
        __classes: new Set((t.attrs.class || '').split(/\s+/).filter(Boolean)),
        value: t.tag === 'textarea' ? (t.inner || '') : (t.attrs.value || ''),
        checked: 'checked' in t.attrs,
        style: {},
        textContent: '',
        get innerHTML() { return this.__html },
        set innerHTML(v) { page.setInner(proxy, String(v)) },
        get classList() {
          const self = this
          return { add: c => self.__classes.add(c), remove: c => self.__classes.delete(c), contains: c => self.__classes.has(c), toggle: c => (self.__classes.has(c) ? self.__classes.delete(c) : self.__classes.add(c)) }
        },
        getAttribute(n) { return n in this.__attrs ? this.__attrs[n] : null },
        setAttribute(n, v) { this.__attrs[n] = String(v) },
        hasAttribute(n) { return n in this.__attrs },
        closest(sel) {
          const m = /^\[([\w-]+)\]$/.exec(sel)
          if (!m) throw new MockError('疑似DOM: closest は [属性] 形式のみ対応: ' + sel)
          for (let e = proxy; e; e = e.__owner) if (m[1] in e.__attrs) return e
          return null
        },
        focus() { page.focused = proxy },
        blur() {},
        addEventListener(type, fn) { (page.listeners[type] = page.listeners[type] || []).push(fn) },
      }
      const proxy = strict(el, '<' + t.tag + '>')
      return proxy
    }
    this.setInner = (el, html) => {
      // 以前この要素の中にあった id 付き要素を消してから作り直す
      for (const [id, e] of Array.from(this.elements)) if (e.__owner === el) this.elements.delete(id)
      el.__html = html
      for (const t of scanTags(html)) if (t.attrs.id) this.elements.set(t.attrs.id, this.makeElement(t, el))
    }

    const body = (/<body[^>]*>([\s\S]*?)<script>/.exec(html) || [])[1] || ''
    const root = this.makeElement({ tag: 'body', attrs: {} })
    this.body = root
    this.setInner(root, body)

    const document = strict({
      getElementById: id => page.elements.get(id) || null,
      addEventListener: (type, fn) => { (page.listeners[type] = page.listeners[type] || []).push(fn) },
      body: root,
    }, 'document')

    const location = strict({
      get href() { return page.currentURL },
      set href(url) {
        // ナビゲーション要求は非同期に shouldAllowRequest へ渡る
        page.timer(() => page.navigate(String(url)), 0, false)
      },
    }, 'location')
    this.currentURL = 'about:blank'

    const ctx = vm.createContext({})
    const g = vm.runInContext('this', ctx)
    Object.assign(g, {
      document: document,
      location: location,
      navigator: { userAgent: 'FakeWebKit' },
      console: {
        log: (...a) => page.logs.push(a.join(' ')),
        warn: (...a) => page.logs.push(a.join(' ')),
        error: (...a) => page.logs.push(a.join(' ')),
      },
      setTimeout: (fn, ms) => page.timer(fn, ms, false),
      setInterval: (fn, ms) => page.timer(fn, ms, true),
      clearTimeout: h => page.clear(h),
      clearInterval: h => page.clear(h),
    })
    g.window = g
    this.ctx = ctx
    this.window = g

    const scripts = []
    const re = /<script>([\s\S]*?)<\/script>/g
    let m
    while ((m = re.exec(html))) scripts.push(m[1])
    scripts.forEach((code, i) => {
      try {
        vm.runInContext(code, ctx, { filename: 'webview-script-' + i + '.js' })
      } catch (e) {
        page.errors.push(e)
      }
    })
  }

  timer(fn, ms, repeat) {
    if (this.disposed) return 0
    const run = () => {
      if (!repeat) this.handles.delete(h)
      try { fn() } catch (e) { this.errors.push(e) }
    }
    const h = repeat ? setInterval(run, ms) : setTimeout(run, ms)
    this.handles.add(h)
    return h
  }

  clear(h) {
    clearTimeout(h)
    clearInterval(h)
    this.handles.delete(h)
  }

  navigate(url) {
    const req = { url: url, method: 'GET', headers: {}, body: null }
    let allow = true
    if (typeof this.wv.shouldAllowRequest === 'function') {
      try {
        allow = this.wv.shouldAllowRequest(req)
      } catch (e) {
        this.env.uncaught.push(e)
        allow = false
      }
    }
    this.navigations.push({ url: url, allowed: allow !== false })
    if (allow !== false) this.errors.push(new Error('ページが別の URL へ遷移しました（画面が消える）: ' + url))
  }

  evaluate(js, useCallback) {
    return new Promise((resolve, reject) => {
      // 本物と同じく非同期に評価する
      setTimeout(() => {
        try {
          if (useCallback) {
            this.window.completion = v => resolve(v)
            vm.runInContext(js, this.ctx)
          } else {
            const v = vm.runInContext(js, this.ctx)
            resolve(v == null || typeof v !== 'object' ? v : JSON.parse(JSON.stringify(v)))
          }
        } catch (e) {
          reject(new Error('Error evaluating JavaScript: ' + e.message))
        }
      }, 0)
    })
  }

  // 画面上のボタンを押す。data-act（と data-id）を持つ要素が今の HTML に無ければ失敗
  click(act, id) {
    let found = null
    for (const el of [this.body].concat(Array.from(this.elements.values()))) {
      for (const t of scanTags(el.innerHTML)) {
        if (t.attrs['data-act'] === act && (id == null || t.attrs['data-id'] === id)) { found = t; break }
      }
      if (found) break
    }
    if (!found) throw new Error('疑似ブラウザ: data-act="' + act + '"' + (id ? ' data-id="' + id + '"' : '') + ' のボタンが画面にありません')
    const target = this.makeElement(found)
    const ev = { type: 'click', target: target, preventDefault() {}, stopPropagation() {} }
    for (const fn of this.listeners.click) {
      try { fn(ev) } catch (e) { this.errors.push(e) }
    }
    return target
  }

  text() {
    const all = [this.body.innerHTML].concat(Array.from(this.elements.values()).map(e => e.innerHTML)).join('\n')
    return all.replace(/<[^>]*>/g, ' ')
  }

  outerHTML() { return this.html }

  dispose() {
    this.disposed = true
    for (const h of this.handles) this.clear(h)
  }
}

module.exports = { createScriptableEnv, MockError }
