// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: purple; icon-glyph: eye;
// TODO View Test.js — 画面の表示方式（全画面 / シート）で「Close」ボタンがどう出るかを比べる
function page(label) {
  return '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' +
    '<body style="margin:0;font-family:-apple-system;background:#F4F5F7;padding:calc(env(safe-area-inset-top) + 20px) 20px">' +
    '<h1 style="font-size:28px">' + label + '</h1>' +
    '<p style="font-size:17px;line-height:1.6">左上や右上に「Close」ボタンが出ているか確認してください。<br>確認したら閉じてください（ボタン、または下にスワイプ）。</p></body>'
}

const a = new Alert()
a.title = '表示方式の比較'
a.message = '①全画面 → ②シート の順に2回画面が出ます。それぞれ Close ボタンの有無を見てください。'
a.addAction('開始')
await a.presentAlert()

const w1 = new WebView()
await w1.loadHTML(page('① 全画面（今の方式）'))
await w1.present(true)

const w2 = new WebView()
await w2.loadHTML(page('② シート表示'))
await w2.present(false)

Script.complete()
