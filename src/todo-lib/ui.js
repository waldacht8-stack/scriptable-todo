// todo-lib/ui.js
// アプリ画面（案1デザイン）。WebView に HTML を表示し、画面側の変更を受け取って保存する。
// 画面 → Scriptable の受け渡しは「window.__next(completion) を繰り返し待つ」ロングポーリング方式。

const CSS = `
/* デザイン（設定の theme）。html と body に theme-xxx クラスを付けて、色・角丸・書体の変数を差し替える */
:root,.theme-clean{
  --bg:#F4F5F7;--card:#FFFFFF;--text:#15181D;--sub:#5A6270;--line:#ECEEF1;--track:#E1E4E9;
  --accent:#1D4ED8;--accent-bg:#E8EEFC;--on-accent:#FFFFFF;--overdue:#C2410C;--overdue-bg:#FDEEE6;--muted:#8A919C;--btn:#15181D;--btn-text:#FFFFFF;
  --r-card:16px;--r-check:15px;--r-check-s:13px;
  --font:-apple-system,"Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;
}
@media (prefers-color-scheme: dark){
  :root,.theme-clean{
    --bg:#0F1115;--card:#1C1F26;--text:#F2F4F7;--sub:#9AA3AF;--line:#2A2F38;--track:#2A2F38;
    --accent:#6EA0FF;--accent-bg:#1E2A44;--on-accent:#0F1115;--overdue:#FB923C;--overdue-bg:#3A2214;--muted:#6B7280;--btn:#F2F4F7;--btn-text:#15181D;
  }
}
/* ナイト：常にダーク、ミント、四角めのチェック */
.theme-night{
  --bg:#0B0D10;--card:#181B21;--text:#F2F4F7;--sub:#9AA3AF;--line:#262A33;--track:#262A33;
  --accent:#34D399;--accent-bg:#11302A;--on-accent:#0B0D10;--overdue:#FB923C;--overdue-bg:#2A1A10;--muted:#6B7280;--btn:#34D399;--btn-text:#0B0D10;
  --r-card:14px;--r-check:8px;--r-check-s:7px;
  --font:-apple-system,"Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;
  color-scheme:dark;
}
/* ポップ：丸い書体、大きな角丸、ティール */
.theme-pop{
  --bg:#F2F7F6;--card:#FFFFFF;--text:#1B1F24;--sub:#59616C;--line:#E3E7EC;--track:#DDE7E5;
  --accent:#0F766E;--accent-bg:#E1F2EF;--on-accent:#FFFFFF;--overdue:#C2410C;--overdue-bg:#FDEEE6;--muted:#8A919C;--btn:#0F766E;--btn-text:#FFFFFF;
  --r-card:24px;--r-check:16px;--r-check-s:14px;
  --font:ui-rounded,"Hiragino Maru Gothic ProN",-apple-system,"Hiragino Sans",sans-serif;
}
@media (prefers-color-scheme: dark){
  .theme-pop{
    --bg:#0E1716;--card:#16211F;--text:#F1F5F4;--sub:#9FB0AD;--line:#24302E;--track:#24302E;
    --accent:#2DD4BF;--accent-bg:#103532;--on-accent:#0E1716;--overdue:#FB923C;--overdue-bg:#3A2214;--muted:#6B7C79;--btn:#2DD4BF;--btn-text:#0E1716;
  }
}
/* モノクロ：白黒だけ。期限切れだけ赤 */
.theme-mono{
  --bg:#FFFFFF;--card:#FFFFFF;--text:#111111;--sub:#6B6B6B;--line:#E5E5E5;--track:#EDEDED;
  --accent:#111111;--accent-bg:#F0F0F0;--on-accent:#FFFFFF;--overdue:#B91C1C;--overdue-bg:#FBEAEA;--muted:#9A9A9A;--btn:#111111;--btn-text:#FFFFFF;
  --r-card:8px;--r-check:15px;--r-check-s:13px;
  --font:-apple-system,"Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;
}
.theme-mono .group{border:1px solid var(--line)}
@media (prefers-color-scheme: dark){
  .theme-mono{
    --bg:#000000;--card:#0D0D0D;--text:#F5F5F5;--sub:#A3A3A3;--line:#262626;--track:#1F1F1F;
    --accent:#F5F5F5;--accent-bg:#1A1A1A;--on-accent:#000000;--overdue:#F87171;--overdue-bg:#2A1212;--muted:#737373;--btn:#F5F5F5;--btn-text:#000000;
  }
}
/* 設定のデザイン選択（色見本つきカード） */
.themes{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.theme-card{border:2px solid var(--line);border-radius:14px;background:var(--bg);padding:10px;display:flex;flex-direction:column;gap:8px;text-align:left;min-height:44px}
.theme-card.on{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent)}
.theme-card b{font-size:14px;color:var(--text)}
.theme-card small{font-size:11px;color:var(--sub)}
.swatch{display:flex;gap:4px;height:22px}
.swatch i{flex:1;border-radius:6px;border:1px solid rgba(127,127,127,.25)}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;background:var(--bg);color:var(--text);
  font-family:var(--font);-webkit-text-size-adjust:100%}
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
.topbar{display:flex;align-items:center;gap:10px;margin-bottom:18px}
.topbar .tabs{flex:1;margin-bottom:0}
.gear{width:46px;height:46px;flex-shrink:0;border:none;border-radius:12px;background:var(--track);color:var(--sub);display:flex;align-items:center;justify-content:center}
.tag{display:flex;align-items:center;gap:3px}
.title .star{color:#E0A100;vertical-align:-2px;margin-right:4px}
.imp-label{display:flex;align-items:center;gap:6px}
.imp-label .star{color:#E0A100}
.celebrate{position:relative;overflow:hidden;display:flex;flex-direction:column;align-items:center;gap:2px;background:var(--accent-bg);color:var(--accent);border-radius:var(--r-card);padding:18px 12px;margin-bottom:20px;animation:pop .5s ease-out}
.celebrate b{font-size:20px;font-weight:800}
.celebrate span{font-size:13px;color:var(--sub)}
.confetti{position:absolute;inset:0;pointer-events:none}
.confetti i{position:absolute;top:-10px;width:7px;height:11px;border-radius:2px;opacity:.9;animation:fall 1.8s ease-in forwards}
.confetti i:nth-child(1){left:8%;background:#1D4ED8;animation-delay:0s}
.confetti i:nth-child(2){left:20%;background:#E0A100;animation-delay:.15s}
.confetti i:nth-child(3){left:33%;background:#C2410C;animation-delay:.3s}
.confetti i:nth-child(4){left:46%;background:#0F766E;animation-delay:.05s}
.confetti i:nth-child(5){left:59%;background:#1D4ED8;animation-delay:.25s}
.confetti i:nth-child(6){left:72%;background:#E0A100;animation-delay:.1s}
.confetti i:nth-child(7){left:84%;background:#C2410C;animation-delay:.35s}
.confetti i:nth-child(8){left:93%;background:#0F766E;animation-delay:.2s}
@keyframes fall{to{transform:translateY(110px) rotate(320deg);opacity:0}}
@keyframes pop{0%{transform:scale(.92);opacity:0}60%{transform:scale(1.03);opacity:1}100%{transform:none}}
.set-row{display:flex;align-items:center;justify-content:space-between;gap:12px}
.set-row input[type=time]{width:120px}
.set-group{display:flex;flex-direction:column;gap:2px}
.set-title{font-size:13px;font-weight:700;color:var(--sub)}
.sheet{max-height:88vh;overflow-y:auto}
.tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:4px;background:var(--track);border-radius:12px;padding:4px;margin-bottom:18px}
.tab{border:none;background:none;border-radius:9px;min-height:38px;font-size:15px;font-weight:700;color:var(--sub)}
.tab.on{background:var(--card);color:var(--text);box-shadow:0 1px 3px rgba(0,0,0,.12)}
.title-row{display:flex;align-items:center;gap:10px;min-height:44px}
.home{display:flex;align-items:center;gap:4px;border:none;background:var(--accent-bg);color:var(--accent);border-radius:18px;padding:0 14px;min-height:36px;font-size:13px;font-weight:700}
.swipe-hint{text-align:center;font-size:12px;color:var(--muted);letter-spacing:.04em}
.note{margin:0 4px 14px;font-size:12px;color:var(--sub)}
section.day{margin-bottom:14px;gap:6px}
.is-today .group{border:2px solid var(--accent)}
.empty-day{padding:0 4px;font-size:13px;color:var(--muted)}
.cal{background:var(--card);border-radius:16px;padding:10px 8px;margin-bottom:18px;touch-action:pan-y}
.week{touch-action:pan-y}
.slide-next{animation:slideNext .25s ease-out}
.slide-prev{animation:slidePrev .25s ease-out}
@keyframes slideNext{from{transform:translateX(40%);opacity:0}to{transform:none;opacity:1}}
@keyframes slidePrev{from{transform:translateX(-40%);opacity:0}to{transform:none;opacity:1}}
.cal-week{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));text-align:center;font-size:12px;font-weight:700;color:var(--sub);margin-bottom:6px}
.cal-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:2px}
.cell{border:none;background:none;border-radius:10px;min-height:52px;padding:4px 0;display:flex;flex-direction:column;align-items:center;gap:3px;font-size:15px;font-weight:600;color:var(--text)}
.cell.blank{visibility:hidden}
.cell .num{width:28px;height:28px;border-radius:14px;display:flex;align-items:center;justify-content:center}
.cell.today .num{background:var(--accent);color:var(--on-accent)}
.cell.sel{background:var(--bg);box-shadow:inset 0 0 0 2px var(--accent)}
.badge{min-width:18px;height:18px;border-radius:9px;padding:0 5px;font-size:11px;font-weight:700;line-height:18px;background:var(--accent);color:var(--on-accent)}
.badge.od{background:var(--overdue)}
.badge.done{background:var(--track);color:var(--sub)}
.badge.none{background:none}
.sun{color:var(--overdue)}
.sat{color:var(--accent)}
.cell.today .num.sun,.cell.today .num.sat{color:var(--on-accent)}
.toast{display:flex;align-items:center;justify-content:space-between;gap:10px;background:var(--btn);color:var(--btn-text);border-radius:14px;padding:10px 10px 10px 16px;font-size:14px;font-weight:600;margin-bottom:16px}
.toast button{background:none;border:1px solid currentColor;color:inherit;border-radius:10px;padding:8px 12px;font-size:14px;font-weight:700;min-height:40px;flex-shrink:0}
.error{background:var(--overdue-bg);color:var(--overdue);border-radius:14px;padding:12px 14px;font-size:13px;font-weight:600;margin-bottom:16px;line-height:1.5}
section{display:flex;flex-direction:column;gap:8px;margin-bottom:20px}
.sec-head{display:flex;align-items:center;gap:8px;padding:0 4px}
.sec-head .dot{width:10px;height:10px;border-radius:5px;background:currentColor}
.sec-head h2{margin:0;font-size:15px;font-weight:700}
.sec-head span{font-size:13px;font-weight:700}
.c-overdue{color:var(--overdue)}.c-today{color:var(--accent)}.c-up{color:var(--sub)}
.group{background:var(--card);border-radius:var(--r-card);overflow:hidden}
.group.overdue{border:2px solid var(--overdue)}
.item{display:flex;align-items:center;gap:14px;padding:14px 16px;min-height:64px;border-bottom:1px solid var(--line)}
.item:last-child{border-bottom:none}
.item.small{min-height:56px;padding:12px 16px}
.check{width:30px;height:30px;flex-shrink:0;border-radius:var(--r-check);color:var(--on-accent);border:2.5px solid var(--accent);background:transparent;padding:0;
  display:flex;align-items:center;justify-content:center;transition:background .2s}
.overdue .check{border-color:var(--overdue)}
.small .check{width:26px;height:26px;border-radius:var(--r-check-s);border-width:2px;border-color:var(--muted)}
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
.btn-save{background:var(--accent);color:var(--on-accent)}
.btn-cancel{background:var(--bg)}
.btn-del{background:var(--overdue-bg);color:var(--overdue)}
.btn-del.armed{background:var(--overdue);color:#fff}
.sheet select{font:inherit;font-size:17px;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:12px;width:100%;min-height:48px}
.sheet .check-row{flex-direction:row;align-items:center;gap:10px;font-size:16px;font-weight:600;color:var(--text);min-height:44px}
.sheet .check-row input{width:24px;height:24px;min-height:0;padding:0;flex-shrink:0;accent-color:var(--accent)}
/* 押したときの手応え */
button{transition:transform .12s,opacity .12s}
button:active{transform:scale(.96);opacity:.75}
.body:active,.cell:active{transform:none;opacity:.55}
.add:active{transform:scale(.97);opacity:1}
/* 完了にした行は少し残してから消す */
.item.leaving{animation:leave .35s ease-in forwards}
.item.leaving .title{text-decoration:line-through;color:var(--sub)}
@keyframes leave{60%{opacity:.6;transform:none}100%{opacity:0;transform:translateX(24px)}}
/* お知らせは追加ボタンの上に浮かせる */
.toast{position:fixed;left:16px;right:16px;bottom:calc(env(safe-area-inset-bottom) + 88px);z-index:5;margin:0;
  box-shadow:0 8px 24px rgba(0,0,0,.22);animation:rise .25s ease-out}
@keyframes rise{from{transform:translateY(16px);opacity:0}to{transform:none;opacity:1}}
/* シート */
.backdrop{animation:fade .2s ease-out}
.sheet{animation:up .25s ease-out}
.grab{align-self:center;width:40px;height:5px;border-radius:3px;background:var(--track);margin:-10px 0 -4px}
@keyframes fade{from{opacity:0}}
@keyframes up{from{transform:translateY(40px);opacity:.4}}
.sheet input::placeholder,.sheet textarea::placeholder{color:var(--muted)}
.sub-hint{font-size:12px;font-weight:400;color:var(--sub)}
`

// 画面側で動くコード。toString() で HTML に埋め込むため、外の変数は参照しない
// （categorize などの model 関数は同じ <script> 内に埋め込まれる）
function clientMain(DATA) {
  const state = {
    todos: DATA.todos, dismissed: [], settings: DATA.settings || {}, showDone: false, sheet: null, toast: DATA.toast,
    view: 'today', weekOffset: 0, monthOffset: 0, selectedDay: null,
  }
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
    send({ type: 'save', todos: state.todos, dismissed: state.dismissed, settings: state.settings })
    // 予備経路：ナビゲーション要求で Scriptable 側に「回収して」と知らせる（shouldAllowRequest で止められる）
    setTimeout(() => { try { window.location.href = 'todoapp://flush' } catch (e) {} }, 0)
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
  }
  const CHECK = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5L20 7"/></svg>'
  const CAL = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>'
  const PLUS = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>'

  const STAR = '<svg class="star" width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-label="重要"><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3l-5.9 3.3 1.3-6.6-4.9-4.6 6.6-.8z"/></svg>'
  const REPEAT = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 2l4 4-4 4"/><path d="M3 11V9a3 3 0 013-3h15"/><path d="M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 01-3 3H3"/></svg>'
  const GEAR = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z"/></svg>'

  function itemHTML(t, now, small) {
    const label = fmtDue(t, now)
    const cal = t.source === 'calendar' || t.pendingEvent ? '<span class="tag">' + CAL + 'カレンダー</span>' : ''
    const rep = t.repeat ? '<span class="tag">' + REPEAT + esc(repeatLabel(t.repeat)) + '</span>' : ''
    return '<div data-row class="item' + (small ? ' small' : '') + (t.done ? ' done' : '') + (t.important ? ' important' : '') + '">' +
      '<button class="check' + (t.done ? ' on' : '') + '" data-act="toggle" data-id="' + esc(t.id) + '" aria-label="' + (t.done ? '未完了に戻す' : '完了にする') + '">' + CHECK + '</button>' +
      '<button class="body" data-act="edit" data-id="' + esc(t.id) + '">' +
      '<div class="title">' + (t.important ? STAR : '') + esc(t.title) + '</div>' +
      '<div class="meta"><span class="time' + (t.due ? '' : ' none') + '">' + esc(label) + '</span>' + cal + rep + '</div>' +
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

  const WEEK = ['日', '月', '火', '水', '木', '金', '土']

  function dayKey(d) {
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
  }

  // 期限のある TODO を日付ごとにまとめる（未完了が先、その中は時刻順）
  function byDay() {
    const map = {}
    for (const t of state.todos) {
      if (!t.due) continue
      const k = dayKey(new Date(t.due))
      if (!map[k]) map[k] = []
      map[k].push(t)
    }
    for (const k of Object.keys(map)) map[k].sort((a, b) => (a.done === b.done ? compareDue(a, b) : a.done ? 1 : -1))
    return map
  }

  function tabsHTML() {
    return '<div class="topbar"><div class="tabs" role="tablist">' + [['today', '今日'], ['week', '週'], ['month', '月']].map(v =>
      '<button role="tab" aria-selected="' + (state.view === v[0]) + '" class="tab' + (state.view === v[0] ? ' on' : '') +
      '" data-act="view" data-id="' + v[0] + '">' + v[1] + '</button>').join('') + '</div>' +
      '<button class="gear" data-act="settings" aria-label="設定">' + GEAR + '</button></div>'
  }

  // 週・月の見出し。期間の切り替えは左右スワイプ。別の期間を見ているときだけ「今週／今月」に戻るボタンを出す
  const BACK = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 010 10h-3"/></svg>'
  function periodHeadHTML(sub, title, remaining, homeLabel, away, unit) {
    return '<div class="head"><div class="head-row"><div><div class="date">' + esc(sub) + '</div>' +
      '<div class="title-row"><h1>' + esc(title) + '</h1>' +
      (away ? '<button class="home" data-act="nav-today">' + BACK + homeLabel + '</button>' : '') + '</div></div>' +
      '<div class="count">残り<b>' + remaining + '</b>件</div></div>' +
      '<div class="swipe-hint">‹ 左右にスワイプで前後の' + unit + 'へ ›</div></div>'
  }

  function undatedNoteHTML() {
    const n = state.todos.filter(t => !t.done && !t.due).length
    return n ? '<p class="note">期限なしのTODO ' + n + '件は「今日」に表示しています</p>' : ''
  }

  function renderToday(now) {
    const g = categorize(state.todos, now)
    const pct = g.stats.total ? Math.round(g.stats.done / g.stats.total * 100) : 0
    let html = '<div class="head"><div class="head-row"><div><div class="date">' + fmtDate(now) + '</div><h1>今日</h1></div>' +
      '<div class="count">残り<b>' + g.stats.remaining + '</b>件</div></div>' +
      '<div class="bar"><i style="width:' + pct + '%"></i></div>' +
      '<div class="ratio">' + (g.stats.total ? g.stats.total + '件中 ' + g.stats.done + '件 完了' : '今日のTODOはまだありません') + '</div></div>'
    if (g.stats.total > 0 && g.stats.remaining === 0) {
      // 今日の分をすべて終えたらお祝い
      html += '<div class="celebrate" role="status">' +
        '<span class="confetti" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span>' +
        '<b>今日は全部完了！</b><span>おつかれさまでした</span></div>'
    }
    html += sectionHTML('c-overdue', '期限切れ', g.overdue, now, { groupClass: 'overdue' })
    html += sectionHTML('c-today', '今日', g.today, now, { showEmpty: '今日のTODOはありません。下のボタンから追加できます' })
    html += sectionHTML('c-up', '今後', g.upcoming, now, { small: true })
    if (g.doneToday.length) {
      html += '<button class="toggle-done" data-act="show-done">' + CHECK.replace('#fff', 'currentColor') +
        (state.showDone ? '完了済みを隠す' : '完了済み ' + g.doneToday.length + '件を表示') + '</button>'
      if (state.showDone) html += '<div class="group">' + g.doneToday.map(t => itemHTML(t, now, true)).join('') + '</div>'
    }
    return html
  }

  // 週：月曜〜日曜の7日分を日付ごとに
  function renderWeek(now) {
    const today = startOfDay(now)
    const mon = addDays(today, -((today.getDay() + 6) % 7) + 7 * state.weekOffset)
    const sun = addDays(mon, 6)
    const map = byDay()
    let remaining = 0
    let body = ''
    for (let i = 0; i < 7; i++) {
      const d = addDays(mon, i)
      const items = map[dayKey(d)] || []
      remaining += items.filter(t => !t.done).length
      const isToday = dayKey(d) === dayKey(today)
      body += '<section class="day' + (isToday ? ' is-today' : '') + '"><div class="sec-head ' + (isToday ? 'c-today' : 'c-up') + '">' +
        '<span class="dot"></span><h2>' + (d.getMonth() + 1) + '/' + d.getDate() + '（' + WEEK[d.getDay()] + '）' + (isToday ? '・今日' : '') + '</h2>' +
        '<span>' + items.length + '</span></div>' +
        (items.length ? '<div class="group">' + items.map(t => itemHTML(t, now, true)).join('') + '</div>' : '<div class="empty-day">TODOなし</div>') +
        '</section>'
    }
    const names = { '-1': '先週', '0': '今週', '1': '来週' }
    const range = (mon.getMonth() + 1) + '/' + mon.getDate() + '〜' + (sun.getMonth() + 1) + '/' + sun.getDate()
    return periodHeadHTML(range, names[state.weekOffset] || range, remaining, '今週', state.weekOffset !== 0, '週') + undatedNoteHTML() +
      '<div class="week' + (state.slide ? ' slide-' + state.slide : '') + '">' + body + '</div>'
  }

  // 月：カレンダー＋選んだ日のTODO
  function renderMonth(now) {
    const today = startOfDay(now)
    const first = new Date(now.getFullYear(), now.getMonth() + state.monthOffset, 1)
    const days = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    const lead = (first.getDay() + 6) % 7 // 月曜始まり
    const map = byDay()
    const sel = state.selectedDay && state.selectedDay.indexOf(dayKey(first).slice(0, 7)) === 0
      ? state.selectedDay
      : (state.monthOffset === 0 ? dayKey(today) : dayKey(first))
    let remaining = 0
    let cells = ''
    for (let i = 0; i < lead; i++) cells += '<span class="cell blank"></span>'
    for (let n = 1; n <= days; n++) {
      const d = new Date(first.getFullYear(), first.getMonth(), n)
      const k = dayKey(d)
      const items = map[k] || []
      const open = items.filter(t => !t.done).length
      remaining += open
      const badge = open
        ? '<span class="badge' + (d < today ? ' od' : '') + '">' + open + '</span>'
        : items.length ? '<span class="badge done">✓</span>' : '<span class="badge none"></span>'
      cells += '<button class="cell' + (k === dayKey(today) ? ' today' : '') + (k === sel ? ' sel' : '') + '" data-act="pick-day" data-id="' + k + '">' +
        '<span class="num' + (d.getDay() === 0 ? ' sun' : d.getDay() === 6 ? ' sat' : '') + '">' + n + '</span>' + badge + '</button>'
    }
    const selDate = new Date(sel + 'T00:00')
    const selItems = map[sel] || []
    let html = periodHeadHTML(first.getFullYear() + '年', (first.getMonth() + 1) + '月', remaining, '今月', state.monthOffset !== 0, '月') + undatedNoteHTML()
    html += '<div class="cal' + (state.slide ? ' slide-' + state.slide : '') + '"><div class="cal-week">' + ['月', '火', '水', '木', '金', '土', '日'].map((w, i) =>
      '<span class="' + (i === 5 ? 'sat' : i === 6 ? 'sun' : '') + '">' + w + '</span>').join('') + '</div>' +
      '<div class="cal-grid">' + cells + '</div></div>'
    html += sectionHTML('c-today', (selDate.getMonth() + 1) + '/' + selDate.getDate() + '（' + WEEK[selDate.getDay()] + '）', selItems, now,
      { small: true, showEmpty: 'この日のTODOはありません' })
    return html
  }

  function render() {
    const now = new Date()
    let html = ''
    if (DATA.error) html += '<div class="error">' + esc(DATA.error) + '</div>'
    if (state.toast) {
      const k = state.toast.kind || 'done'
      const msg = k === 'snooze' ? '「' + esc(state.toast.title) + '」を10分後にもう一度通知します'
        : k === 'info' ? esc(state.toast.title)
        : '「' + esc(state.toast.title) + '」を完了しました'
      html += '<div class="toast"><span>' + msg + '</span>' + (k === 'done' ? '<button data-act="undo-toast">元に戻す</button>' : '') + '</div>'
    }
    html += tabsHTML()
    html += state.view === 'week' ? renderWeek(now) : state.view === 'month' ? renderMonth(now) : renderToday(now)
    html += '<button class="add" data-act="add">' + PLUS + 'TODOを追加</button>'
    document.getElementById('app').innerHTML = html
    state.slide = null // スライドのアニメーションは切り替えた直後の1回だけ
  }

  function toInputDate(d) {
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
  }

  function openSheet(t) {
    state.sheet = { id: t ? t.id : null, armed: false }
    const isCal = t && (t.source === 'calendar' || t.pendingEvent)
    const d = t && t.due ? new Date(t.due) : null
    let html = '<div class="backdrop" data-act="close"></div><form class="sheet" onsubmit="return false">'
    html += '<div class="grab"></div><h3>' + (t ? 'TODOを編集' : 'TODOを追加') + '</h3>'
    if (isCal) {
      html += '<div class="ro">' + esc(t.title) + '<small>' + esc(fmtDue(t, new Date())) + '・' + esc(t.calendarTitle || 'カレンダー') + '</small></div>' +
        '<p class="hint">タイトルや日時の変更はカレンダーアプリで行ってください（自動で反映されます）</p>'
    } else {
      html += '<label>タイトル<input id="f-title" type="text" enterkeyhint="done" placeholder="例：牛乳を買う" value="' + esc(t ? t.title : '') + '"></label>' +
        '<div class="row2"><label>日付<input id="f-date" type="date" value="' + (d ? toInputDate(d) : '') + '"></label>' +
        '<label>時刻<input id="f-time" type="time" value="' + (d && !t.allDay ? pad2(d.getHours()) + ':' + pad2(d.getMinutes()) : '') + '"></label></div>' +
        '<button type="button" class="link" data-act="clear-date">期限なしにする</button>'
      if (!t && DATA.calendars && DATA.calendars.length) {
        html += '<label class="check-row"><input id="f-cal" type="checkbox" data-act="toggle-cal">カレンダーにも予定として登録</label>' +
          '<label id="f-calrow" style="display:none">登録先カレンダー<select id="f-calname">' +
          DATA.calendars.map(c => '<option value="' + esc(c) + '">' + esc(c) + '</option>').join('') + '</select></label>'
      }
      const rep = (t && t.repeat) || ''
      html += '<label>繰り返し<select id="f-repeat">' +
        [['', 'なし'], ['daily', '毎日'], ['weekdays', '平日（月〜金）'], ['weekly', '毎週'], ['monthly', '毎月']].map(o =>
          '<option value="' + o[0] + '"' + (o[0] === rep ? ' selected' : '') + '>' + o[1] + '</option>').join('') + '</select></label>'
    }
    html += '<label class="check-row"><input id="f-imp" type="checkbox"' + (t && t.important ? ' checked' : '') + '>' +
      '<span class="imp-label">' + STAR + '重要<span class="sub-hint">一覧とウィジェットの先頭に固定</span></span></label>'
    html += '<label>メモ<textarea id="f-note" placeholder="任意">' + esc(t ? t.note : '') + '</textarea></label>'
    html += '<div class="actions">' +
      (t ? '<button type="button" class="btn-del" data-act="delete">削除</button>' : '') +
      '<button type="button" class="btn-cancel" data-act="close">キャンセル</button>' +
      '<button type="button" class="btn-save" data-act="save">保存</button></div></form>'
    const el = document.getElementById('sheet')
    el.innerHTML = html
    if (!t) setTimeout(() => { const f = document.getElementById('f-title'); if (f) f.focus() }, 50)
  }

  function closeSheet() {
    // 設定でデザインを試しただけで閉じたら、保存済みのデザインに戻す
    if (state.sheet && state.sheet.settings) applyTheme(state.settings.theme || 'clean')
    state.sheet = null
    document.getElementById('sheet').innerHTML = ''
  }

  function saveSheet() {
    const stamp = new Date().toISOString()
    const existing = state.sheet.id ? state.todos.find(x => x.id === state.sheet.id) : null
    const note = document.getElementById('f-note').value
    const impEl = document.getElementById('f-imp')
    const important = !!(impEl && impEl.checked)
    if (existing && (existing.source === 'calendar' || existing.pendingEvent)) {
      existing.note = note
      existing.important = important
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
      const repEl = document.getElementById('f-repeat')
      const repeat = (repEl && repEl.value) || null
      if (repeat && !due) {
        // 繰り返しには起点の日付が要るので、日付なしなら今日の終日にする
        due = new Date(toInputDate(new Date()) + 'T00:00')
        allDay = true
      }
      const fields = {
        title: title, due: due ? due.toISOString() : null, allDay: allDay, note: note, updatedAt: stamp,
        repeat: repeat, repeatDay: repeat && due ? due.getDate() : null, important: important,
      }
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

  function showToast(toast) {
    state.toast = toast
    setTimeout(() => { if (state.toast === toast) { state.toast = null; if (!state.sheet) render() } }, 6000)
  }

  // ===== デザイン =====
  // [名前, 表示名, 説明, 色見本（背景・カード・アクセント・期限切れ）]
  const THEMES = [
    ['clean', 'クリーン', '白いカードと青', ['#F4F5F7', '#FFFFFF', '#1D4ED8', '#C2410C']],
    ['night', 'ナイト', '黒とミント（常にダーク）', ['#0B0D10', '#181B21', '#34D399', '#FB923C']],
    ['pop', 'ポップ', '丸い書体とティール', ['#F2F7F6', '#FFFFFF', '#0F766E', '#C2410C']],
    ['mono', 'モノクロ', '白黒のミニマル', ['#FFFFFF', '#F0F0F0', '#111111', '#B91C1C']],
  ]

  function applyTheme(name) {
    let root = null
    try { root = document.documentElement } catch (e) { /* 取れない環境では body だけ */ }
    for (const el of [document.body, root]) {
      if (!el) continue
      for (const t of THEMES) el.classList.remove('theme-' + t[0])
      el.classList.add('theme-' + name)
    }
  }

  function themeCardsHTML(cur) {
    return '<div class="themes">' + THEMES.map(t =>
      '<button type="button" id="theme-' + t[0] + '" class="theme-card' + (t[0] === cur ? ' on' : '') + '" data-act="pick-theme" data-id="' + t[0] + '">' +
      '<span class="swatch">' + t[3].map(c => '<i style="background:' + c + '"></i>').join('') + '</span>' +
      '<b>' + t[1] + '</b><small>' + t[2] + '</small></button>').join('') + '</div>'
  }

  // 選んだデザインをその場で反映（保存するまでは試し）
  function pickTheme(name) {
    if (!state.sheet || !state.sheet.settings) return
    state.sheet.theme = name
    for (const t of THEMES) {
      const card = document.getElementById('theme-' + t[0])
      if (card) card.classList[t[0] === name ? 'add' : 'remove']('on')
    }
    applyTheme(name)
  }

  // ===== 設定 =====
  function timeValue(h, m) {
    return pad2(h) + ':' + pad2(m || 0)
  }

  function options(list, cur) {
    return list.map(o => '<option value="' + o[0] + '"' + (String(o[0]) === String(cur) ? ' selected' : '') + '>' + o[1] + '</option>').join('')
  }

  function openSettings() {
    const s = state.settings
    state.sheet = { settings: true, theme: s.theme || 'clean' }
    let html = '<div class="backdrop" data-act="close"></div><form class="sheet" onsubmit="return false"><div class="grab"></div><h3>設定</h3>' +
      '<div class="set-title">デザイン（アプリとウィジェット）</div>' + themeCardsHTML(state.sheet.theme) + '<div class="set-title">通知</div>'
    html += '<div class="set-row"><label class="check-row"><input id="s-morning-on" type="checkbox"' + (s.morningHour != null ? ' checked' : '') + '>朝の通知（今日のTODO）</label>' +
      '<input id="s-morning" type="time" value="' + timeValue(s.morningHour == null ? 7 : s.morningHour, s.morningMinute) + '"></div>'
    html += '<div class="set-row"><label class="check-row"><input id="s-evening-on" type="checkbox"' + (s.eveningHour != null ? ' checked' : '') + '>夜の通知（残りのTODO）</label>' +
      '<input id="s-evening" type="time" value="' + timeValue(s.eveningHour == null ? 20 : s.eveningHour, s.eveningMinute) + '"></div>'
    html += '<label>期限前のリマインド<select id="s-remind">' + options([['off', '通知しない'], [0, '期限ちょうど'], [10, '10分前'], [15, '15分前'],
      [30, '30分前'], [60, '1時間前'], [120, '2時間前']], s.remindMinutes == null ? 'off' : s.remindMinutes) + '</select></label>'
    html += '<div class="set-title">カレンダー</div><label>取り込む範囲<select id="s-range">' + options([[14, '2週間先まで'], [30, '30日先まで'], [45, '45日先まで'],
      [60, '60日先まで'], [90, '90日先まで']], s.lookaheadDays) + '</select></label>'
    const cals = DATA.allCalendars || []
    if (cals.length) {
      const ex = s.excludeCalendars || []
      html += '<div class="set-group"><div class="set-title">取り込むカレンダー</div>' + cals.map((c, i) =>
        '<label class="check-row"><input id="s-cal-' + i + '" type="checkbox"' + (ex.indexOf(c) < 0 ? ' checked' : '') + '>' + esc(c) + '</label>').join('') + '</div>'
    }
    html += '<div class="actions"><button type="button" class="btn-cancel" data-act="close">キャンセル</button>' +
      '<button type="button" class="btn-save" data-act="save-settings">保存</button></div></form>'
    document.getElementById('sheet').innerHTML = html
  }

  function saveSettings() {
    const get = id => document.getElementById(id)
    const hm = (onId, timeId) => {
      const m = /^(\d{1,2}):(\d{2})/.exec(get(timeId).value || '')
      return get(onId).checked && m ? [Number(m[1]), Number(m[2])] : [null, 0]
    }
    const cur = state.settings
    const morning = hm('s-morning-on', 's-morning')
    const evening = hm('s-evening-on', 's-evening')
    const remind = get('s-remind').value
    const range = Number(get('s-range').value)
    const s = Object.assign({}, cur, {
      morningHour: morning[0], morningMinute: morning[1], eveningHour: evening[0], eveningMinute: evening[1],
      remindMinutes: remind === '' ? cur.remindMinutes : remind === 'off' ? null : Number(remind),
      lookaheadDays: range || cur.lookaheadDays,
    })
    const cals = DATA.allCalendars || []
    if (cals.length) {
      // 一覧に出ていない除外（既定の祝日など）は残し、一覧に出ているものはチェックの状態に合わせる
      const keep = (cur.excludeCalendars || []).filter(c => cals.indexOf(c) < 0)
      s.excludeCalendars = keep.concat(cals.filter((c, i) => !get('s-cal-' + i).checked))
    }
    s.theme = state.sheet.theme || s.theme
    state.settings = s
    closeSheet()
    showToast({ kind: 'info', title: '設定を保存しました' })
    render()
    persist()
  }

  function deleteFromSheet(btn) {
    if (!state.sheet.armed) {
      state.sheet.armed = true
      btn.classList.add('armed')
      btn.textContent = 'もう一度押すと削除'
      return
    }
    const t = state.todos.find(x => x.id === state.sheet.id)
    if (t && t.source === 'calendar') state.dismissed.push({ key: t.eventKey, due: t.due })
    state.todos = state.todos.filter(x => x.id !== state.sheet.id)
    closeSheet()
    render()
    persist()
  }

  // 週・月表示：左右スワイプ（または ‹ ›）で前後の期間へ。縦スクロールと区別するため、横にはっきり動いたときだけ
  function movePeriod(step) {
    if (state.view === 'week') state.weekOffset += step
    else if (state.view === 'month') state.monthOffset += step
    else return
    state.slide = step > 0 ? 'next' : 'prev'
    render()
  }
  let touch = null
  document.addEventListener('touchstart', e => {
    const p = e.changedTouches && e.changedTouches[0]
    touch = (state.view === 'month' || state.view === 'week') && !state.sheet && p ? { x: p.clientX, y: p.clientY } : null
  })
  document.addEventListener('touchend', e => {
    const p = e.changedTouches && e.changedTouches[0]
    if (!touch || !p) return
    const dx = p.clientX - touch.x
    const dy = p.clientY - touch.y
    touch = null
    if (Math.abs(dx) >= 60 && Math.abs(dx) > Math.abs(dy) * 1.5) movePeriod(dx < 0 ? 1 : -1)
  })

  document.addEventListener('click', e => {
    const el = e.target.closest('[data-act]')
    if (!el) return
    const act = el.getAttribute('data-act')
    const id = el.getAttribute('data-id')
    const t = id ? state.todos.find(x => x.id === id) : null
    if (act === 'toggle' && t) {
      if (t.done) {
        uncompleteTodo(state.todos, t, new Date())
        render()
        persist()
      } else {
        el.classList.add('on')
        const row = el.closest && el.closest('[data-row]')
        if (row) row.classList.add('leaving')
        setTimeout(() => {
          // 繰り返しなら次の回が追加される
          completeTodo(state.todos, t, new Date())
          render()
          persist()
        }, 350)
      }
    } else if (act === 'edit' && t) openSheet(t)
    else if (act === 'settings') openSettings()
    else if (act === 'save-settings') saveSettings()
    else if (act === 'add') openSheet(null)
    else if (act === 'show-done') { state.showDone = !state.showDone; render() }
    else if (act === 'close') closeSheet()
    else if (act === 'pick-theme') pickTheme(id)
    else if (act === 'save') saveSheet()
    else if (act === 'delete') deleteFromSheet(el)
    else if (act === 'view') {
      state.view = id
      render()
    }
    else if (act === 'nav') {
      movePeriod(Number(id))
    }
    else if (act === 'nav-today') {
      state.weekOffset = 0
      state.monthOffset = 0
      state.selectedDay = null
      render()
    }
    else if (act === 'pick-day') {
      state.selectedDay = id
      render()
    }
    else if (act === 'undo-toast') {
      const u = state.toast && state.todos.find(x => x.id === state.toast.id)
      if (u) {
        uncompleteTodo(state.todos, u, new Date())
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
  if (DATA.toast) showToast(DATA.toast) // ウィジェット・通知から開いたときのお知らせは6秒で消す
}

function buildHTML(data, model, error, calendars, toast, allCalendars) {
  const helpers = ['startOfDay', 'addDays', 'pad2', 'fmtTime', 'fmtDate', 'fmtDue', 'compareDue', 'compareTodo', 'categorize', 'newId',
    'repeatLabel', 'nextOccurrence', 'completeTodo', 'uncompleteTodo']
    .map(name => model[name].toString()).join('\n')
  const payload = JSON.stringify({ todos: data.todos, error: error || null, calendars: calendars || [], toast: toast || null,
    settings: data.settings || {}, allCalendars: allCalendars || [] }).replace(/</g, '\\u003c')
  const theme = ['clean', 'night', 'pop', 'mono'].indexOf((data.settings || {}).theme) >= 0 ? data.settings.theme : 'clean'
  return '<!doctype html><html lang="ja" class="theme-' + theme + '"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">' +
    '<style>' + CSS + '</style></head><body class="theme-' + theme + '"><div id="app"></div><div id="sheet"></div>' +
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
  const html = buildHTML(data, ctx.model, ctx.error, ctx.calendars, ctx.toast, ctx.allCalendars)
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
