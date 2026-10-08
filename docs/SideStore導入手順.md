# SideStore 導入とアプリ版のインストール手順

正式アプリ版（段階0：検証用）を iPhone に入れるための手順。最初の1回だけ PC が必要。

参照：SideStore 公式 https://docs.sidestore.io/docs/installation/prerequisites ・ https://docs.sidestore.io/docs/installation/install

## 0. 前もって知っておくこと
- SideStore と iloader は、Apple 公式ではない有志のツール。Apple ID でのサインインが必要（不安なら、このためだけの別の Apple ID を作って使う）
- 無料の Apple ID では、SideStore で入れられるアプリは **同時に3つまで**（SideStore 自身も1つ使う）
- 署名の期限は **7日**。期限内に SideStore で更新すれば延びる（5. で自動化）
- アプリの入れ替え・更新のときは、iPhone の **LocalDevVPN をオン** にしておく。Wi-Fi が必要

## 1. iPhone の準備（5分）
1. App Store で **LocalDevVPN** を入れる
2. 設定アプリ → **プライバシーとセキュリティ** → 一番下の **デベロッパモード** → オン（再起動を求められたら再起動し、再起動後の確認で「オンにする」）

## 2. PC の準備（10分）
1. **iTunes** を入れる：Apple のサイト https://www.apple.com/itunes/download/win64 から（Microsoft Store 版でも可）
2. **iloader** を入れる：https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi をダウンロードして実行

## 3. SideStore を iPhone に入れる（10分）
1. iPhone を USB ケーブルで PC につなぐ。iPhone に「このコンピュータを信頼しますか？」と出たら **信頼** → パスコード
2. PC で **iloader** を開く → **Add Account** → Apple ID でサインイン（大文字・小文字も正確に）
3. 一覧から自分の iPhone を選ぶ → **Install SideStore (Stable)** → 終わるまで待つ
4. iPhone：設定 → **一般** → **VPNとデバイス管理** → 「デベロッパApp」の自分の Apple ID → **信頼**
5. iPhone：**LocalDevVPN** を開いて接続（パスコードを求められたら入力）
6. **SideStore** を開いて Apple ID でサインイン → **My Apps** → 「7 DAYS」の表示をタップして更新できれば成功

ここまで終われば、PC と USB ケーブルはもう不要。

## 4. アプリ版を入れる（3分）
1. iPhone の **Safari** で次を開き、IPA をダウンロードする
   https://github.com/waldacht8-stack/scriptable-todo/releases/download/ios-latest/TodoApp.ipa
2. **LocalDevVPN** を接続
3. **SideStore** → **My Apps** → 左上の **＋** → 「ファイル」の **ダウンロード** にある **TodoApp.ipa** を選ぶ → インストールが終わるまで待つ
4. ホーム画面の **TODO** を開く

新しいビルドが出たら、同じ手順で入れ直す（上書きされ、データは残る）。

## 5. 署名の自動更新（5分）
1. **ショートカット** → **オートメーション** → **＋** → **時刻**（例：毎日 3:00、繰り返し「毎日」）→ **すぐに実行**、「実行時に通知」オフ
2. アクションを順に追加する
   - **VPN を設定**（または LocalDevVPN のアクション）→ LocalDevVPN を **接続**
   - SideStore の **Refresh All Apps**（すべてのアプリを更新）
3. **完了**

※ 実際のアクション名は、SideStore・LocalDevVPN のバージョンで違うことがある。入れたあと、表示された名前に合わせて調整する。

## 6. 段階0で確かめること（アプリを入れたら）
| 確認すること | 見るところ |
| --- | --- |
| App Group（アプリとウィジェットのデータ共有） | TODO タブ上部が「App Group：使える」になるか |
| ウィジェットの選択 | ホーム画面を長押し → ＋ → 「TODO」で検索 → 「TODO」「起床」の2種類が選べるか |
| ウィジェット上の操作 | TODO ウィジェットの丸をタップ → アプリを開かずに完了になるか。起床ウィジェットの「起きた！」 |
| AlarmKit | 起床タブ → 「1分後にテストアラーム」→ 許可 → 画面をロック・マナーモードで鳴るか |
| 自動更新 | 数日後、SideStore の My Apps の残り日数が「7 DAYS」に戻っているか |
