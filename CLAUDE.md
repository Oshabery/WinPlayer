# DeskLink

iPad (iPadOS 17+) 用のリモートデスクトップ（RDP）クライアント。iPadOS では仮想化・JIT が使えず Windows をネイティブ実行できないため、
Windows PC／クラウドに RDP で接続して操作する方式を採っている。RDP プロトコルは FreeRDP 3、UI は SwiftUI + UIKit。

## ビルドとテスト（Mac）

```bash
brew install cmake ninja xcodegen
./scripts/build-openssl.sh      # build/openssl/<sdk>
./scripts/build-freerdp.sh      # Vendor/include, Vendor/<sdk>/lib/libFreeRDPAll.a
xcodegen                        # project.yml から DeskLink.xcodeproj を生成（コミットしない）
xcodebuild test -scheme DeskLink -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Mac での一括準備は `./scripts/setup-mac.sh [--test]`。CI は `.github/workflows/ios.yml`（macOS でライブラリ→アプリ→シミュレーターテスト。失敗内容は `scripts/ci-annotate.sh` でエラー注釈に出す）。
`build/`、`Vendor/`、`*.xcodeproj/` は生成物なので .gitignore 済み。

## 構成

- `Bridge/DLSession.{h,c}` — FreeRDP の薄い C ラッパー。Swift へはブリッジングヘッダー経由で公開（ヘッダーは FreeRDP に依存しない）
- `App/Services/RDPSession.swift` — 接続1本の管理（@Observable）。C コールバックの受け口
- `App/Rendering/` — `Framebuffer`（スレッドセーフなピクセルバッファ）と `RemoteDesktopView`（CADisplayLink 描画、ズーム／座標変換）
- `App/Input/` — タッチ・ポインタ・キーボード入力 → RDP 入力。`ScancodeMap` は USB HID 使用コード → セット1スキャンコード（拡張キーは 0x100）
- `App/Views/` — SwiftUI 画面と補助キーバー
- `Tests/` — XCTest 単体テスト

## 設計上のルール

- FreeRDP の API は接続スレッドからのみ呼ぶ。UI からの入力は `dl_send_*` → 内部キュー → 接続スレッドで送信
- WinPR は auto-reset イベント未対応。イベントは manual-reset で作り、待機後に `ResetEvent` する
- `CHANNEL_RDPSND` はビルドから外さない（ネットワーク自動検出／ハートビートで rdpdr と `rdpsnd sys:fake` が自動で読み込まれる）
- 証明書はアプリ側（`CertificateTrust`）で管理し、FreeRDP には常に「今回のみ許可」を返す
- 再接続は新しい `RDPSession` を作って行う（古い接続の通知が混ざらないように）
- UI 文言は日本語

## 検証メモ

- Linux でも FreeRDP を `-DWITH_UNICODE_BUILTIN=ON` 付きでビルドすれば、C ブリッジのコンパイル・リンク・接続ライフサイクルを検証できる
- Swift コードのビルド・テストには Mac（Xcode）が必要

## Context Management & Development Efficiency

* Before reading an entire file, search with grep and read only the relevant sections needed for the task.
* Use subagents for codebase exploration and independent research whenever appropriate. Return only concise summaries and relevant findings to the main context.
* Show diffs instead of entire files when reporting code changes. Never dump entire files unless explicitly requested.
* Do not repeat decisions, explanations, or information already established in the current session.
* When switching tasks significantly or when context becomes large, suggest using `/compact` or starting a fresh session when appropriate.
* Keep responses concise by default. Provide detailed explanations only when necessary or explicitly requested.
* After making code changes, run relevant tests and verification steps to ensure correctness. Report the results, failures, and any unverified areas.
