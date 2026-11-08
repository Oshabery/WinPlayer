# DeskLink — iPad 用リモートデスクトップクライアント

iPad から Windows PC（またはクラウド上の Windows）に **RDP（リモートデスクトップ プロトコル）** で接続し、
タッチ・トラックパッド・キーボードで操作するアプリです。

> iPadOS ではアプリから仮想化（Hypervisor）や JIT が使えないため、iPad 上で Windows を直接動かすことはできません。
> そのため、Windows は PC やクラウドで動かし、画面と入力を iPad とやり取りする方式にしています。

## 機能（v0.1）

- 接続先の登録・編集（SwiftData）、パスワードは Keychain に保存
- ネットワークレベル認証（NLA）／TLS、初回接続時のサーバー証明書の確認と記憶
- 解像度: 画面に合わせる／1280×800／1920×1080／2560×1440
- タッチ操作
  | 操作 | 動作 |
  |---|---|
  | 1本指タップ | 左クリック |
  | 2本指タップ | 右クリック |
  | 長押ししてドラッグ | 左ボタンを押したままドラッグ |
  | 1本指で動かす | マウスカーソル移動 |
  | 2本指で動かす | スクロール |
  | ピンチ | 拡大・縮小 |
  | 3本指で動かす | 拡大中の表示位置を移動 |
- トラックパッド・マウス: 移動、左／右／中クリック、Control+クリックで右クリック、スクロール
- ハードウェアキーボード: 物理キーをそのまま送信（日本語 JIS 配列対応、Command → Windows キー、Option → Alt）
- ソフトウェアキーボード + 補助キーバー（Esc / Tab / Ctrl / Alt / Win / 矢印 / Home / End / PgUp / PgDn / Del / F1〜F12）
- Ctrl+Alt+Del の送信

## 必要なもの

- Mac（Xcode 15 以降）、iPadOS 17 以降の iPad（またはシミュレーター）
- Homebrew で `cmake`、`ninja`、`xcodegen`
- 接続先: リモートデスクトップを有効にした Windows（Pro / Enterprise / Server。Home エディションはホストになれません）

## ビルド手順（Mac）

```bash
brew install cmake ninja xcodegen
```

```bash
./scripts/build-openssl.sh
```

```bash
./scripts/build-freerdp.sh
```

```bash
xcodegen
```

```bash
open DeskLink.xcodeproj
```

1. `build-openssl.sh` が OpenSSL 3.3.2 を、`build-freerdp.sh` が FreeRDP 3.10.3 を iPad 実機（arm64）とシミュレーター（arm64）向けにビルドし、
   `Vendor/include` と `Vendor/<sdk>/lib/libFreeRDPAll.a` を作ります（初回は 10〜20 分程度）。
2. Xcode で Signing & Capabilities のチームを設定し、iPad またはシミュレーターで実行します。
3. 単体テスト:

```bash
xcodebuild test -scheme DeskLink -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

バージョンは環境変数 `OPENSSL_VERSION` / `FREERDP_VERSION` / `MIN_IOS` で変更できます。

## Windows 側の準備

1. 「設定 > システム > リモート デスクトップ」をオンにする
2. PC 名または IP アドレスを確認する（同じ Wi-Fi／LAN から接続）
3. Microsoft アカウントでサインインしている場合、ユーザー名はメールアドレス、パスワードは Microsoft アカウントのパスワード
   （Windows Hello の PIN では接続できません）

外出先から使う場合は、ルーターでポートを公開せず、VPN（Tailscale など）経由で接続することを強くおすすめします。

## 構成

```
App/
  DeskLinkApp.swift               アプリのエントリーポイント
  Models/                         Connection（SwiftData）、HostAddress（アドレス解析）
  Services/RDPSession.swift       FreeRDP 接続1本を管理（@Observable）。C ブリッジを呼ぶ
  Services/KeychainStore.swift    パスワード保存
  Services/CertificateTrust.swift 信頼したサーバー証明書の記憶
  Rendering/Framebuffer.swift     リモート画面のピクセルバッファ（スレッドセーフ）
  Rendering/FramebufferView.swift 表示ビュー（CADisplayLink で更新、ズーム／パン、座標変換）
  Input/                          タッチ・ポインタ・キーボード入力 → RDP 入力
  Views/                          SwiftUI 画面、補助キーバー
Bridge/
  DLSession.h / .c                FreeRDP 3 の薄い C ラッパー（接続スレッド、入力キュー、描画コールバック）
scripts/                          OpenSSL / FreeRDP のクロスビルド
Tests/                            単体テスト
```

スレッドの流れ: `DLSession` は専用スレッドで FreeRDP のイベントループを回します。UI スレッドからの入力はキューに積んで
そのスレッドで送信し、画面の更新範囲は `Framebuffer` にコピーされ、`CADisplayLink` がメインスレッドで描画します。

## 現時点の制限と今後の予定

- リモートのマウスカーソル画像は表示していません（トラックパッドでは iPad のポインタがそのまま見えます）
- グラフィックスパイプライン（RDP GFX / H.264）未対応のため、高解像度では帯域を多く使います
- 未対応: 音声出力、クリップボード共有、ウィンドウサイズ変更への自動追従（display control）、RD ゲートウェイ、
  ソフトウェアキーボードでの日本語変換中の文字表示
- バックグラウンドに移ると接続は切れます（再接続ボタンで戻れます）

## ライセンスについて

FreeRDP と OpenSSL はどちらも Apache License 2.0 です。配布する際は、両者のライセンス表記をアプリ内に含めてください。
