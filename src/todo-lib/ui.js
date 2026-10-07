// todo-lib/ui.js
// アプリ画面（案1デザイン）。WebView に HTML を表示し、画面側の変更を受け取って保存する。
// 画面 → Scriptable の受け渡しは「window.__next(completion) を繰り返し待つ」ロングポーリング方式。

const CSS = `
:root{
  --bg:#F4F5F7;--card:#FFFFFF;--text:#15181D;--sub:#5A6270;--line:#ECEEF1;--track:#E1E4E9;
  --accent:#1D4ED8;--overdue:#C2410C;--overdue-bg:#FDEEE6;--muted:#8A919C;--btn:#15181D;--btn-text:#FFFFFF;
}
@media (prefers-color-scheme: dark){
  :root{
    --bg:#0F1115;--card:#1C1F26;--text:#F2F4F7;--sub:#9AA3AF;--line:#2A2F38;--track:#2A2F38;
    --accent:#6EA0FF;--overdue:#FB923C;--overdue-bg:#3A2214;--muted:#6B7280;--btn:#F2F4F7;--btn-text:#15181D;
  }
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;background:var(--bg);color:var(--text);
  font-family:-apple-system,"Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;-webkit-text-size-adjust:100%}
button{font-family:inherit;color:inherit}
#app{padding:calc(env(safe-area-inset-top) + 20px) 16px calc(env(safe-area-inset-bottom) + 110px)}
.head{padding:0 4px 18px;display:flex;flex-direction:column;gap:12px}
.head-row{display:flex;align-items:flex-end;justify-content:space-between}
.date{font-size:15px;font-weight:600;color:var(--sub)}
h1{margin:2px 0 0;font-size:34px;font-weight:800;letter-spacing:.02em}
.count{display:flex;align-items:baseline;gap:4px;color:var(--sub);font-size:15px}
.count b{font-size:40px;font-weight:800;line-height:1;color:var(--accent)}
.bar{height:8px;border-radius:4px;background:var(--track);overflow:hidden}
.bar i{display:block;height:8px;border-radius:4px;background:var(--accent);transition:width .3s}
.ratio{font-size:13px;color:var(--sub)}
.toast{display:flex;align-items:center;justify-content:space-between;gap:10px;background:var(--btn);color:var(--btn-text);border-radius:14px;padding:10px 10px 10px 16px;font-size:14px;font-weight:600;margin-bottom:16px}
.toast button{background:none;border:1px solid currentColor;color:inherit;border-radius:10px;padding:8px 12px;font-size:14px;font-weight:700;min-height:40px;flex-shrink:0}
.error{background:var(--overdue-bg);color:var(--overdue);border-radius:14px;padding:12px 14px;font-size:13px;font-weight:600;margin-bottom:16px;line-height:1.5}
section{display:flex;flex-direction:column;gap:8px;margin-bottom:20px}
.sec-head{display:flex;align-items:center;gap:8px;padding:0 4px}
.sec-head .dot{width:10px;height:10px;border-radius:5px;background:currentColor}
.sec-head h2{margin:0;font-size:15px;font-weight:700}
.sec-head span{font-size:13px;font-weight:700}
.c-overdue{color:var(--overdue)}.c-today{color:var(--accent)}.c-up{color:var(--sub)}
.group{background:var(--card);border-radius:16px;overflow:hidden}
.group.overdue{border:2px solid var(--overdue)}
.item{display:flex;align-items:center;gap:14px;padding:14px 16px;min-height:64px;border-bottom:1px solid var(--line)}
.item:last-child{border-bottom:none}
.item.small{min-height:56px;padding:12px 16px}
.check{width:30px;height:30px;flex-shrink:0;border-radius:15px;border:2.5px solid var(--accent);background:transparent;padding:0;
  display:flex;align-items:center;justify-content:center;transition:background .2s}
.overdue .check{border-color:var(--overdue)}
.small .check{width:26px;height:26px;border-radius:13px;border-width:2px;border-color:var(--muted)}
.check svg{opacity:0;transition:opacity .2s}
.check.on{background:var(--accent);border-color:var(--accent)}
.overdue .check.on{background:var(--overdue)}
.check.on svg{opacity:1}
.body{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:3px;background:none;border:none;padding:4px 0;text-align:left}
.title{font-size:17px;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.small .title{font-size:16px;font-weight:500}
.meta{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--sub)}
.meta .time{font-weight:700;color:var(--accent)}
.overdue .meta .time{color:var(--overdue)}
.meta .time.none{font-weight:400;color:var(--sub)}
.small .meta .time{font-weight:400;color:var(--sub)}
.item.done .title{text-decoration:line-through;color:var(--sub);font-weight:500}
.empty{padding:18px 16px;font-size:14px;color:var(--sub)}
.toggle-done{display:flex;align-items:center;gap:6px;background:none;border:none;padding:4px;font-size:14px;color:var(--sub);min-height:44px}
.add{position:fixed;left:20px;right:20px;bottom:calc(env(safe-area-inset-bottom) + 20px);height:56px;border:none;border-radius:28px;
  background:var(--btn);color:var(--btn-text);font-size:17px;font-weight:700;display:flex;align-items:center;justify-content:center;gap:8px;
  box-shadow:0 6px 20px rgba(0,0,0,.18)}
.backdrop{position:fixed;inset:0;background:rgba(0,0,0,.35)}
.sheet{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-radius:22px 22px 0 0;
  padding:22px 20px calc(env(safe-area-inset-bottom) + 20px);display:flex;flex-direction:column;gap:14px}
.sheet h3{margin:0;font-size:18px;font-weight:800}
.sheet label{display:flex;flex-direction:column;gap:6px;font-size:13px;font-weight:700;color:var(--sub)}
.sheet input,.sheet textarea{font:inherit;font-size:17px;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:12px;width:100%;min-height:48px}
.sheet textarea{min-height:72px;resize:none}
.row2{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px}
.ro{background:var(--bg);border-radius:12px;padding:12px;font-size:16px;font-weight:700;color:var(--text);line-height:1.5}
.ro small{display:block;font-size:13px;font-weight:400;color:var(--sub)}
.hint{margin:0;font-size:12px;color:var(--sub)}
.link{align-self:flex-start;background:none;border:none;color:var(--accent);font-size:14px;padding:4px 0;min-height:36px}
.actions{display:flex;gap:10px;margin-top:4px}
.actions button{flex:1;height:50px;border-radius:14px;border:none;font-size:16px;font-weight:700}
.btn-save{background:var(--accent);color:#fff}
.btn-cancel{background:var(--bg)}
.btn-del{background:var(--overdue-bg);color:var(--overdue)}
.btn-del.armed{background:var(--overdue);color:#fff}
.sheet select{font:inherit;font-size:17px;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:12px;width:100%;min-height:48px}
.sheet .check-row{flex-direction:row;align-items:center;gap:10px;font-size:16px;font-weight:600;color:var(--text);min-height:44px}
.sheet .check-row input{width:24px;height:24px;min-height:0;padding:0;flex-shrink:0;accent-color:var(--accent)}
`

// 画面側で動くコード。toString() で HTML に埋め込むため、外の変数は参照しない
// （categorize などの model 関数は同じ <script> 内に埋め込まれる）
function clientMain(DATA) {
  const state = { todos: DATA.todos, dismissed: [], showDone: false, sheet: null, toast: DATA.toast }
  const queue = []
  let waiter = null

  function send(msg) {
    if (msg.type === 'save') {
      for (let i = queue.length - 1; i >= 0; i--) if (queue[i].type === 'save') queue.splice(i, 1)
    }
    if (waiter) {
      const w = waiter
      waiter = null
      w(JSON.stringify(msg))
    } else {
      queue.push(msg)
    }
  }
  window.__next = function (cb) {
    if (queue.length) cb(JSON.stringify(queue.shift()))
    else waiter = cb
  }
  window.__drain = function () {
    const last = queue.filter(m => m.type === 'save').pop()
    queue.length = 0
    return last ? JSON.stringify(last) : ''
  }
  function persist() {
    send({ type: 'save', todos: state.todos, dismissed: state.dismissed })
    // 予備経路：ナビゲーション要求で Scriptable 側に「回収して」と知らせる（shouldAllowRequest で止められる）
    setTimeout(() => { try { window.location.href = 'todoapp://flush' } catch (e) {} }, 0)
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
  }
  const CHECK = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5L20 7"/></svg>'
  const CAL = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>'
  const PLUS = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>'

  function itemHTML(t, now, small) {
    const label = fmtDue(t, now)
    const cal = t.source === 'calendar' || t.pendingEvent ? '<span style="display:flex;align-items:center;gap:4px">' + CAL + 'カレンダー</span>' : ''
    return '<div class="item' + (small ? ' small' : '') + (t.done ? ' done' : '') + '">' +
      '<button class="check' + (t.done ? ' on' : '') + '" data-act="toggle" data-id="' + esc(t.id) + '" aria-label="' + (t.done ? '未完了に戻す' : '完了にする') + '">' + CHECK + '</button>' +
      '<button class="body" data-act="edit" data-id="' + esc(t.id) + '">' +
      '<div class="title">' + esc(t.title) + '</div>' +
      '<div class="meta"><span class="time' + (t.due ? '' : ' none') + '">' + esc(label) + '</span>' + cal + '</div>' +
      '</button></div>'
  }

  function sectionHTML(cls, name, items, now, opts) {
    const o = opts || {}
    if (!items.length && !o.showEmpty) return ''
    const body = items.length
      ? items.map(t => itemHTML(t, now, o.small)).join('')
      : '<div class="empty">' + o.showEmpty + '</div>'
    return '<section><div class="sec-head ' + cls + '"><span class="dot"></span><h2>' + name + '</h2><span>' + items.length + '</span></div>' +
      '<div class="group' + (o.groupClass ? ' ' + o.groupClass : '') + '">' + body + '</div></section>'
  }

  function render() {
    const now = new Date()
    const g = categorize(state.todos, now)
    const pct = g.stats.total ? Math.round(g.stats.done / g.stats.total * 100) : 0
    let html = ''
    if (DATA.error) html += '<div class="error">' + esc(DATA.error) + '</div>'
    if (state.toast) html += '<div class="toast"><span>「' + esc(state.toast.title) + '」を完了しました</span><button data-act="undo-toast">元に戻す</button></div>'
    html += '<div class="head"><div class="head-row"><div><div class="date">' + fmtDate(now) + '</div><h1>今日</h1></div>' +
      '<div class="count">残り<b>' + g.stats.remaining + '</b>件</div></div>' +
      '<div class="bar"><i style="width:' + pct + '%"></i></div>' +
      '<div class="ratio">' + g.stats.done + ' / ' + g.stats.total + ' 件 完了</div></div>'
    html += sectionHTML('c-overdue', '期限切れ', g.overdue, now, { groupClass: 'overdue' })
    html += sectionHTML('c-today', '今日', g.today, now, { showEmpty: '今日のTODOはありません' })
    html += sectionHTML('c-up', '今後', g.upcoming, now, { small: true })
    if (g.doneToday.length) {
      html += '<button class="toggle-done" data-act="show-done">' + CHECK.replace('#fff', 'currentColor') +
        (state.showDone ? '完了済みを隠す' : '完了済み ' + g.doneToday.length + '件を表示') + '</button>'
      if (state.showDone) html += '<div class="group">' + g.doneToday.map(t => itemHTML(t, now, true)).join('') + '</div>'
    }
    html += '<button class="add" data-act="add">' + PLUS + 'TODOを追加</button>'
    document.getElementById('app').innerHTML = html
  }

  function toInputDate(d) {
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
  }

  function openSheet(t) {
    state.sheet = { id: t ? t.id : null, armed: false }
    const isCal = t && (t.source === 'calendar' || t.pendingEvent)
    const d = t && t.due ? new Date(t.due) : null
    let html = '<div class="backdrop" data-act="close"></div><form class="sheet" onsubmit="return false">'
    html += '<h3>' + (t ? 'TODOを編集' : 'TODOを追加') + '</h3>'
    if (isCal) {
      html += '<div class="ro">' + esc(t.title) + '<small>' + esc(fmtDue(t, new Date())) + '・' + esc(t.calendarTitle || 'カレンダー') + '</small></div>' +
        '<p class="hint">タイトルや日時の変更はカレンダーアプリで行ってください（自動で反映されます）</p>'
    } else {
      html += '<label>タイトル<input id="f-title" type="text" enterkeyhint="done" value="' + esc(t ? t.title : '') + '"></label>' +
        '<div class="row2"><label>日付<input id="f-date" type="date" value="' + (d ? toInputDate(d) : '') + '"></label>' +
        '<label>時刻<input id="f-time" type="time" value="' + (d && !t.allDay ? pad2(d.getHours()) + ':' + pad2(d.getMinutes()) : '') + '"></label></div>' +
        '<button type="button" class="link" data-act="clear-date">期限なしにする</button>'
      if (!t && DATA.calendars && DATA.calendars.length) {
        html += '<label class="check-row"><input id="f-cal" type="checkbox" data-act="toggle-cal">カレンダーにも予定として登録</label>' +
          '<label id="f-calrow" style="display:none">登録先カレンダー<select id="f-calname">' +
          DATA.calendars.map(c => '<option value="' + esc(c) + '">' + esc(c) + '</option>').join('') + '</select></label>'
      }
    }
    html += '<label>メモ<textarea id="f-note">' + esc(t ? t.note : '') + '</textarea></label>'
    html += '<div class="actions">' +
      (t ? '<button type="button" class="btn-del" data-act="delete">削除</button>' : '') +
      '<button type="button" class="btn-cancel" data-act="close">キャンセル</button>' +
      '<button type="button" class="btn-save" data-act="save">保存</button></div></form>'
    const el = document.getElementById('sheet')
    el.innerHTML = html
    if (!t) setTimeout(() => { const f = document.getElementById('f-title'); if (f) f.focus() }, 50)
  }

  function closeSheet() {
    state.sheet = null
    document.getElementById('sheet').innerHTML = ''
  }

  function saveSheet() {
    const stamp = new Date().toISOString()
    const existing = state.sheet.id ? state.todos.find(x => x.id === state.sheet.id) : null
    const note = document.getElementById('f-note').value
    if (existing && (existing.source === 'calendar' || existing.pendingEvent)) {
      existing.note = note
      existing.updatedAt = stamp
    } else {
      const titleEl = document.getElementById('f-title')
      if (!titleEl) return
      const title = titleEl.value.trim()
      if (!title) {
        titleEl.focus()
        return
      }
      const date = document.getElementById('f-date').value
      const time = document.getElementById('f-time').value
      let due = null
      let allDay = false
      if (date && time) due = new Date(date + 'T' + time)
      else if (date) { due = new Date(date + 'T00:00'); allDay = true }
      else if (time) due = new Date(toInputDate(new Date()) + 'T' + time)
      const calEl = document.getElementById('f-cal')
      const toCalendar = !existing && calEl && calEl.checked
      if (toCalendar && !due) {
        // 日時なしでカレンダー登録を選んだら、今日の終日予定にする
        due = new Date(toInputDate(new Date()) + 'T00:00')
        allDay = true
      }
      const fields = { title: title, due: due ? due.toISOString() : null, allDay: allDay, note: note, updatedAt: stamp }
      if (existing) Object.assign(existing, fields)
      else {
        const todo = Object.assign({ id: newId(), done: false, doneAt: null, source: 'manual', createdAt: stamp }, fields)
        // 予定の作成は Scriptable 側が行う（値は登録先カレンダー名。空なら既定のカレンダー）
        if (toCalendar) todo.pendingEvent = document.getElementById('f-calname').value || true
        state.todos.push(todo)
      }
    }
    closeSheet()
    render()
    persist()
  }

  function deleteFromSheet(btn) {
    if (!state.sheet.armed) {
      state.sheet.armed = true
      btn.classList.add('armed')
      btn.textContent = '本当に削除'
      return
    }
    const t = state.todos.find(x => x.id === state.sheet.id)
    if (t && t.source === 'calendar') state.dismissed.push({ key: t.eventKey, due: t.due })
    state.todos = state.todos.filter(x => x.id !== state.sheet.id)
    closeSheet()
    render()
    persist()
  }

  document.addEventListener('click', e => {
    const el = e.target.closest('[data-act]')
    if (!el) return
    const act = el.getAttribute('data-act')
    const id = el.getAttribute('data-id')
    const t = id ? state.todos.find(x => x.id === id) : null
    if (act === 'toggle' && t) {
      if (t.done) {
        t.done = false
        t.doneAt = null
        t.updatedAt = new Date().toISOString()
        render()
        persist()
      } else {
        el.classList.add('on')
        setTimeout(() => {
          t.done = true
          t.doneAt = new Date().toISOString()
          t.updatedAt = t.doneAt
          render()
          persist()
        }, 350)
      }
    } else if (act === 'edit' && t) openSheet(t)
    else if (act === 'add') openSheet(null)
    else if (act === 'show-done') { state.showDone = !state.showDone; render() }
    else if (act === 'close') closeSheet()
    else if (act === 'save') saveSheet()
    else if (act === 'delete') deleteFromSheet(el)
    else if (act === 'undo-toast') {
      const u = state.toast && state.todos.find(x => x.id === state.toast.id)
      if (u) {
        u.done = false
        u.doneAt = null
        u.updatedAt = new Date().toISOString()
        persist()
      }
      state.toast = null
      render()
    }
    else if (act === 'toggle-cal') {
      const row = document.getElementById('f-calrow')
      if (row) row.style.display = el.checked ? '' : 'none'
    }
    else if (act === 'clear-date') {
      document.getElementById('f-date').value = ''
      document.getElementById('f-time').value = ''
    }
  })

  render()
  setInterval(() => { if (!state.sheet) render() }, 60000) // 時間経過で「期限切れ」へ移るのを反映
  if (state.toast) setTimeout(() => { state.toast = null; if (!state.sheet) render() }, 6000) // 完了のお知らせは6秒で消す
}

function buildHTML(data, model, error, calendars, toast) {
  const helpers = ['startOfDay', 'addDays', 'pad2', 'fmtTime', 'fmtDate', 'fmtDue', 'compareDue', 'categorize', 'newId']
    .map(name => model[name].toString()).join('\n')
  const payload = JSON.stringify({ todos: data.todos, error: error || null, calendars: calendars || [], toast: toast || null }).replace(/</g, '\\u003c')
  return '<!doctype html><html lang="ja"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">' +
    '<style>' + CSS + '</style></head><body><div id="app"></div><div id="sheet"></div>' +
    '<script>\n' + helpers + '\n' + clientMain.toString() + '\nclientMain(' + payload + ')\n</script></body></html>'
}

function timeout(ms) {
  return new Promise(resolve => {
    const t = new Timer()
    t.timeInterval = ms
    t.schedule(() => resolve(null))
  })
}

// ctx: { model, error, onMessage(msg) }
// 受け渡しは2経路：①画面からのナビゲーション要求（todoapp://flush）をきっかけに __drain で回収
// ②3秒ごとの定期回収。コールバック待ちの evaluateJavaScript は表示を止める恐れがあるので使わない。
// どちらで届いても保存処理は1本の直列キューで順に実行する。
async function present(data, ctx) {
  const wv = new WebView()
  let chain = Promise.resolve()
  function handle(raw) {
    if (!raw) return chain
    chain = chain.then(() => ctx.onMessage(JSON.parse(raw))).catch(e => console.error('保存エラー: ' + e))
    return chain
  }
  function drain() {
    return wv.evaluateJavaScript('window.__drain ? window.__drain() : ""').then(handle, e => console.error('回収エラー: ' + e))
  }
  // 回収が終わる前に次の回収を重ねない
  let busy = false
  function pollDrain() {
    if (busy) return
    busy = true
    drain().then(() => { busy = false }, () => { busy = false })
  }
  // shouldAllowRequest の中で evaluateJavaScript を呼ぶと WebKit が固まることがあるので、
  // 判定だけ返して回収は Timer で後回しにする。url が無い場合でも例外を出さない。
  wv.shouldAllowRequest = request => {
    const url = String((request && request.url) || '')
    if (url.indexOf('todoapp://') === 0) {
      Timer.schedule(0, false, () => { pollDrain() })
      return false
    }
    return true
  }
  console.log('画面: HTML生成')
  const html = buildHTML(data, ctx.model, ctx.error, ctx.calendars, ctx.toast)
  console.log('画面: HTML読み込み (' + html.length + '文字)')
  await wv.loadHTML(html)
  console.log('画面: 表示開始')
  // 予備経路：3秒ごとに未回収の変更を取りに行く
  const poll = new Timer()
  poll.timeInterval = 3000
  poll.repeats = true
  poll.schedule(() => { pollDrain() })
  await wv.present(true)
  poll.invalidate()
  console.log('画面: 閉じた')
  // 閉じる直前に送りきれなかった変更があれば回収する
  try {
    await Promise.race([drain(), timeout(1500)])
  } catch (e) {
    // 画面が破棄済みなら何もしない
  }
  await chain
}

module.exports = { present, buildHTML }
