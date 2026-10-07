// todo-lib/widget.js
// ホーム画面（小・中・大）とロック画面（円形・長方形・1行）のウィジェット。デザインは案1。

function palette() {
  const dyn = (light, dark) => Color.dynamic(new Color(light), new Color(dark))
  return {
    bg: dyn('#FFFFFF', '#1C1F26'),
    text: dyn('#15181D', '#F2F4F7'),
    sub: dyn('#5A6270', '#9AA3AF'),
    accent: dyn('#1D4ED8', '#6EA0FF'),
    overdue: dyn('#C2410C', '#FB923C'),
    overdueText: dyn('#9A3412', '#FDBA74'),
    overdueBg: dyn('#FDEEE6', '#3A2214'),
    line: dyn('#ECEEF1', '#2A2F38'),
  }
}

function text(stack, value, size, color, opts) {
  const o = opts || {}
  const t = stack.addText(String(value))
  t.font = o.weight === 'heavy' ? Font.heavySystemFont(size) : o.weight === 'regular' ? Font.systemFont(size) : Font.boldSystemFont(size)
  if (color) t.textColor = color
  t.lineLimit = o.lines || 1
  if (o.minScale) t.minimumScaleFactor = o.minScale
  return t
}

function circle(stack, color, size) {
  const img = stack.addImage(SFSymbol.named('circle').image)
  img.imageSize = new Size(size, size)
  img.tintColor = color
  return img
}

// 進捗バー（DrawContext は動的カラー非対応なので固定色）
function progressBar(width, height, ratio) {
  const dc = new DrawContext()
  dc.size = new Size(width, height)
  dc.opaque = false
  dc.respectScreenScale = true
  const r = height / 2
  const bg = new Path()
  bg.addRoundedRect(new Rect(0, 0, width, height), r, r)
  dc.addPath(bg)
  dc.setFillColor(new Color('#8E949C', 0.3))
  dc.fillPath()
  if (ratio > 0) {
    const fg = new Path()
    fg.addRoundedRect(new Rect(0, 0, Math.max(height, width * ratio), height), r, r)
    dc.addPath(fg)
    dc.setFillColor(new Color('#2F6BEF'))
    dc.fillPath()
  }
  return dc.getImage()
}

function row(parent, t, color, label, labelColor, size, C) {
  const r = parent.addStack()
  r.layoutHorizontally()
  r.centerAlignContent()
  r.spacing = 7
  circle(r, color, size - 2)
  text(r, t.title, size, C.text)
  r.addSpacer()
  if (label) text(r, label, size - 3, labelColor)
  // 行をタップ → そのTODOを完了にしてアプリを開く（中・大サイズのみ有効。小・ロック画面は全体の url）
  r.url = doneURL(t)
  return r
}

function doneURL(t) {
  return URLScheme.forRunningScript() + '?action=done&id=' + encodeURIComponent(t.id)
}

function overduePill(parent, count, C) {
  const p = parent.addStack()
  p.backgroundColor = C.overdueBg
  p.cornerRadius = 8
  p.setPadding(4, 8, 4, 8)
  p.centerAlignContent()
  p.spacing = 5
  circle(p, C.overdue, 8)
  text(p, '期限切れ ' + count + '件', 12, C.overdueText)
  return p
}

function buildSmall(w, g, now, model, C) {
  w.setPadding(16, 16, 16, 16)
  text(w, '今日の残り', 13, C.sub)
  w.addSpacer()
  const n = w.addStack()
  n.bottomAlignContent()
  n.spacing = 4
  text(n, g.stats.remaining, 56, C.accent, { weight: 'heavy' })
  text(n, '件', 16, C.sub)
  w.addSpacer()
  if (g.overdue.length) {
    overduePill(w, g.overdue.length, C)
  } else {
    const next = model.nextItem(g, now)
    text(w, next ? model.fmtDue(next, now) + ' ' + next.title : 'すべて完了', 12, C.sub, { minScale: 0.8 })
  }
}

function buildMedium(w, g, now, model, C) {
  w.setPadding(14, 16, 14, 16)
  const h = w.addStack()
  h.layoutHorizontally()
  h.spacing = 14

  const left = h.addStack()
  left.layoutVertically()
  left.size = new Size(70, 0)
  text(left, (now.getMonth() + 1) + '/' + now.getDate() + '（' + ['日', '月', '火', '水', '木', '金', '土'][now.getDay()] + '）', 12, C.sub)
  left.addSpacer()
  text(left, g.stats.remaining, 44, C.accent, { weight: 'heavy' })
  text(left, '残り', 12, C.sub)

  const right = h.addStack()
  right.layoutVertically()
  right.spacing = 8
  const items = g.overdue.map(t => ({ t: t, od: true })).concat(g.today.map(t => ({ t: t, od: false })))
  if (!items.length) {
    right.addSpacer()
    text(right, '今日のTODOはすべて完了', 15, C.sub)
    right.addSpacer()
    return
  }
  for (const x of items.slice(0, 3)) {
    if (x.od) row(right, x.t, C.overdue, '期限切れ', C.overdue, 15, C)
    else row(right, x.t, C.accent, x.t.due ? model.fmtDue(x.t, now) : '', C.accent, 15, C)
  }
  right.addSpacer()
  if (items.length > 3) text(right, 'ほか ' + (items.length - 3) + '件', 11, C.sub)
}

function buildLarge(w, g, now, model, C) {
  w.setPadding(18, 18, 18, 18)
  const head = w.addStack()
  head.bottomAlignContent()
  text(head, '今日のTODO', 20, C.text, { weight: 'heavy' })
  head.addSpacer()
  text(head, '残り ', 14, C.sub)
  text(head, g.stats.remaining, 22, C.accent, { weight: 'heavy' })
  text(head, ' / ' + g.stats.total, 14, C.sub)
  w.addSpacer(10)
  const ratio = g.stats.total ? g.stats.done / g.stats.total : 0
  const bar = w.addImage(progressBar(320, 6, ratio))
  bar.imageSize = new Size(320, 6)
  w.addSpacer(12)

  let rows = 0
  const max = 8
  if (g.overdue.length) {
    text(w, '期限切れ', 12, C.overdue)
    w.addSpacer(6)
    for (const t of g.overdue.slice(0, 2)) {
      const box = w.addStack()
      box.backgroundColor = C.overdueBg
      box.cornerRadius = 10
      box.setPadding(7, 10, 7, 10)
      row(box, t, C.overdue, model.fmtDue(t, now), C.overdueText, 15, C)
      w.addSpacer(4)
      rows++
    }
    w.addSpacer(8)
  }
  text(w, '今日', 12, C.accent)
  w.addSpacer(6)
  if (!g.today.length) text(w, 'なし', 14, C.sub)
  const shown = g.today.slice(0, max - rows)
  for (const t of shown) {
    const box = w.addStack()
    box.setPadding(5, 10, 5, 10)
    row(box, t, C.accent, t.due ? model.fmtDue(t, now) : '—', t.due ? C.accent : C.sub, 15, C)
  }
  const hidden = g.today.length - shown.length
  if (hidden > 0) text(w, '　ほか ' + hidden + '件', 11, C.sub)
  w.addSpacer()
  const tomorrow = model.addDays(model.startOfDay(now), 1)
  const t2 = g.upcoming.find(t => new Date(t.due) < model.addDays(tomorrow, 1))
  if (t2) text(w, '明日：' + t2.title + (t2.allDay ? '' : ' ' + model.fmtTime(new Date(t2.due))), 12, C.sub)
}

function buildCircular(w, g) {
  w.addAccessoryWidgetBackground = true
  const s = w.addStack()
  s.layoutVertically()
  s.centerAlignContent()
  const a = s.addStack()
  a.addSpacer()
  text(a, g.stats.remaining, 24, null, { weight: 'heavy' })
  a.addSpacer()
  const b = s.addStack()
  b.addSpacer()
  text(b, '残り', 10, null)
  b.addSpacer()
}

function buildRectangular(w, g, now, model) {
  const next = model.nextItem(g, now)
  text(w, '次のTODO', 11, null)
  text(w, next ? (next.due ? model.fmtDue(next, now) + ' ' : '') + next.title : 'なし', 15, null, { weight: 'heavy', minScale: 0.7 })
  text(w, g.overdue.length ? '期限切れ ' + g.overdue.length + '件' : '残り ' + g.stats.remaining + '件', 11, null)
}

function buildInline(w, g, now, model) {
  const next = model.nextItem(g, now)
  text(w, '残り' + g.stats.remaining + '件' + (next ? '・次 ' + (next.due ? model.fmtDue(next, now) + ' ' : '') + next.title : ''), 12, null)
}

function build(data, family, now, model, errorMessage) {
  const C = palette()
  const g = model.categorize(data.todos, now)
  const w = new ListWidget()
  w.url = URLScheme.forRunningScript()
  w.refreshAfterDate = new Date(now.getTime() + 15 * 60000)
  const f = family || 'medium'
  if (f === 'accessoryCircular') buildCircular(w, g)
  else if (f === 'accessoryRectangular') buildRectangular(w, g, now, model)
  else if (f === 'accessoryInline') buildInline(w, g, now, model)
  else {
    w.backgroundColor = C.bg
    if (f === 'small') buildSmall(w, g, now, model, C)
    else if (f === 'large' || f === 'extraLarge') buildLarge(w, g, now, model, C)
    else buildMedium(w, g, now, model, C)
    if (errorMessage) {
      w.addSpacer(2)
      text(w, '同期エラー：アプリを開いて確認', 9, C.overdue)
    }
  }
  return w
}

// データファイルすら読めないときの表示
function buildError(message) {
  const w = new ListWidget()
  w.url = URLScheme.forRunningScript()
  w.refreshAfterDate = new Date(Date.now() + 15 * 60000)
  text(w, 'TODO', 14, null)
  text(w, message, 11, null, { lines: 4, weight: 'regular' })
  return w
}

module.exports = { build, buildError }
