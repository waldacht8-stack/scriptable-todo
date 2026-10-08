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
  t.font = o.weight === 'heavy' ? Font.heavySystemFont(size)
    : o.weight === 'regular' ? Font.systemFont(size)
    : o.weight === 'semibold' ? Font.semiboldSystemFont(size)
    : o.weight === 'medium' ? Font.mediumSystemFont(size)
    : Font.boldSystemFont(size)
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


function star(stack, size) {
  const img = stack.addImage(SFSymbol.named('star.fill').image)
  img.imageSize = new Size(size, size)
  img.tintColor = new Color('#E0A100')
  return img
}

function row(parent, t, color, label, labelColor, size, C) {
  const r = parent.addStack()
  r.layoutHorizontally()
  r.centerAlignContent()
  r.spacing = 7
  circle(r, color, size - 2)
  if (t.important) star(r, size - 4)
  text(r, t.title, size, C.text, { weight: 'semibold' })
  r.addSpacer()
  if (label) text(r, label, size - 3, labelColor, { weight: 'medium' })
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
  text(p, '期限切れ ' + count + '件', 12, C.overdueText, { weight: 'semibold' })
  return p
}

// 次の期限（時刻つき・未来）までの残り時間。数字は iOS が秒単位で減らすので、ウィジェットの更新を待たない
function addNextLeft(parent, next, size, labelColor, timeColor, stacked) {
  if (!next) return null
  const s = parent.addStack()
  if (stacked) s.layoutVertically()
  else {
    s.layoutHorizontally()
    s.centerAlignContent()
    s.spacing = 4
  }
  text(s, '次の期限まで', size - 2, labelColor)
  const d = s.addDate(new Date(next.due))
  d.applyTimerStyle()
  d.font = Font.boldSystemFont(size)
  d.textColor = timeColor
  d.lineLimit = 1
  return s
}

// 期限の近さで色を分ける：期限切れ＝オレンジ、今日中＝青、それ以降・期限なし＝灰
function dueColor(t, now, model, C) {
  if (model.isOverdue(t, now)) return C.overdue
  if (t.due && new Date(t.due) < model.addDays(model.startOfDay(now), 1)) return C.accent
  return C.sub
}

function dueLabel(t, now, model) {
  return t.due ? model.fmtDue(t, now) : '期限なし'
}

function countHead(parent, d, size, C) {
  const n = parent.addStack()
  n.bottomAlignContent()
  n.spacing = 3
  text(n, d.items.length, size, C.accent, { weight: 'heavy' })
  text(n, '件', Math.round(size / 3.2), C.sub)
}

function emptyLine(parent, d, C) {
  parent.addSpacer()
  if (d.celebrate) {
    text(parent, '全部完了！', 20, C.accent, { weight: 'heavy' })
    text(parent, 'おつかれさまでした', 12, C.sub, { weight: 'medium' })
  } else {
    text(parent, 'やることはありません', 15, C.sub, { weight: 'medium' })
  }
  parent.addSpacer()
}

// 小：件数を大きく、その下に一番近いTODOを1件
function buildSmall(w, d, now, model, C) {
  w.setPadding(14, 16, 14, 16)
  const top = w.addStack()
  top.centerAlignContent()
  text(top, '未完了', 13, C.sub, { weight: 'semibold' })
  top.addSpacer()
  if (d.overdue) text(top, '⚠︎ ' + d.overdue, 13, C.overdue)
  countHead(w, d, 44, C)
  w.addSpacer()
  const first = d.items[0]
  if (d.celebrate && !first) text(w, '全部完了！', 15, C.accent, { weight: 'heavy' })
  else if (d.celebrate) text(w, '今日の分は完了！', 13, C.accent, { minScale: 0.8 })
  else if (!first) text(w, 'やることはありません', 12, C.sub, { weight: 'medium', minScale: 0.8 })
  else {
    // カウントダウンを出すときは高さが足りないのでタイトルは1行
    text(w, first.title, 14, C.text, { weight: 'semibold', lines: d.next ? 1 : 2, minScale: 0.85 })
    w.addSpacer(2)
    text(w, dueLabel(first, now, model), 12, dueColor(first, now, model, C), { weight: 'medium' })
  }
  if (d.next) {
    w.addSpacer(4)
    addNextLeft(w, d.next, 12, C.sub, C.text, false)
  }
}

function buildMedium(w, d, now, model, C) {
  w.setPadding(14, 16, 14, 16)
  const h = w.addStack()
  h.layoutHorizontally()
  h.spacing = 14

  const left = h.addStack()
  left.layoutVertically()
  left.size = new Size(76, 0)
  text(left, '未完了', 12, C.sub, { weight: 'semibold' })
  left.addSpacer()
  countHead(left, d, 40, C)
  if (d.celebrate) text(left, '今日の分は完了', 11, C.accent, { minScale: 0.8 })
  else if (d.overdue) text(left, '⚠︎ 期限切れ ' + d.overdue, 11, C.overdue, { minScale: 0.8 })
  if (d.next) {
    left.addSpacer(6)
    addNextLeft(left, d.next, 13, C.sub, C.text, true)
  }

  const right = h.addStack()
  right.layoutVertically()
  right.spacing = 8
  if (!d.items.length) return emptyLine(right, d, C)
  for (const t of d.items.slice(0, 3)) {
    const c = dueColor(t, now, model, C)
    row(right, t, c, dueLabel(t, now, model), c, 15, C)
  }
  right.addSpacer()
  if (d.items.length > 3) text(right, 'ほか ' + (d.items.length - 3) + '件 ›', 11, C.sub, { weight: 'medium' })
}

function buildLarge(w, d, now, model, C) {
  w.setPadding(18, 18, 18, 18)
  const head = w.addStack()
  head.bottomAlignContent()
  const title = head.addStack()
  title.layoutVertically()
  text(title, model.fmtDate(now) + '・期限が近い順', 12, C.sub, { weight: 'semibold' })
  text(title, 'やること', 20, C.text, { weight: 'heavy' })
  head.addSpacer()
  text(head, '未完了 ', 13, C.sub, { weight: 'medium' })
  countHead(head, d, 24, C)
  w.addSpacer(6)
  const info = w.addStack()
  info.centerAlignContent()
  if (d.celebrate) text(info, '今日の分は全部完了！', 13, C.accent)
  else if (d.overdue) overduePill(info, d.overdue, C)
  info.addSpacer()
  if (d.next) addNextLeft(info, d.next, 12, C.sub, C.text, false)
  w.addSpacer(10)

  if (!d.items.length) return emptyLine(w, d, C)
  const max = 8
  for (const t of d.items.slice(0, max)) {
    const c = dueColor(t, now, model, C)
    const box = w.addStack()
    box.setPadding(5, 10, 5, 10)
    box.cornerRadius = 10
    if (model.isOverdue(t, now)) box.backgroundColor = C.overdueBg
    row(box, t, c, dueLabel(t, now, model), model.isOverdue(t, now) ? C.overdueText : c, 15, C)
    w.addSpacer(3)
  }
  if (d.items.length > max) text(w, '　ほか ' + (d.items.length - max) + '件 ›', 11, C.sub, { weight: 'medium' })
  w.addSpacer()
}

function buildCircular(w, d) {
  w.addAccessoryWidgetBackground = true
  const s = w.addStack()
  s.layoutVertically()
  s.centerAlignContent()
  const a = s.addStack()
  a.addSpacer()
  text(a, d.items.length, 24, null, { weight: 'heavy' })
  a.addSpacer()
  const b = s.addStack()
  b.addSpacer()
  text(b, '未完了', 9, null)
  b.addSpacer()
}

function buildRectangular(w, d, now, model) {
  const first = d.items[0]
  text(w, first ? '次のTODO・' + dueLabel(first, now, model) : 'TODO', 11, null, { weight: 'semibold' })
  text(w, first ? first.title : 'やることはありません', 15, null, { weight: 'heavy', minScale: 0.7 })
  text(w, (d.overdue ? '⚠︎ 期限切れ ' + d.overdue + '件・' : '') + '未完了 ' + d.items.length + '件', 11, null, { weight: 'medium' })
}

function buildInline(w, d, now, model) {
  const first = d.items[0]
  text(w, first ? dueLabel(first, now, model) + ' ' + first.title + '（残り' + d.items.length + '）' : 'やることはありません', 12, null)
}

function build(data, family, now, model, errorMessage) {
  const C = palette()
  const d = model.byDeadline(data.todos, now)
  const g = model.categorize(data.todos, now)
  d.celebrate = g.stats.total > 0 && g.stats.remaining === 0 // 今日の分をすべて終えた
  // 24時間より先のカウントダウンは「49:12:03」のように読みにくいので出さない（行の期限ラベルで足りる）
  if (d.next && new Date(d.next.due) - now > 24 * 3600e3) d.next = null
  const w = new ListWidget()
  w.url = URLScheme.forRunningScript()
  w.refreshAfterDate = new Date(now.getTime() + 15 * 60000)
  const f = family || 'medium'
  if (f === 'accessoryCircular') buildCircular(w, d)
  else if (f === 'accessoryRectangular') buildRectangular(w, d, now, model)
  else if (f === 'accessoryInline') buildInline(w, d, now, model)
  else {
    w.backgroundColor = C.bg
    if (f === 'small') buildSmall(w, d, now, model, C)
    else if (f === 'large' || f === 'extraLarge') buildLarge(w, d, now, model, C)
    else buildMedium(w, d, now, model, C)
    if (errorMessage) {
      w.addSpacer(2)
      text(w, '⚠︎ 同期できませんでした（タップして確認）', 9, C.overdue)
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
