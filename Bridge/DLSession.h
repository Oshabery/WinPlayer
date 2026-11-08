// DLSession: FreeRDP をSwiftから扱いやすくするための薄いCラッパー。
// このヘッダーはFreeRDPのヘッダーに依存しないので、Swiftのブリッジングヘッダーからそのまま読み込める。
#ifndef DL_SESSION_H
#define DL_SESSION_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DLSession DLSession;

typedef enum {
    DL_STATE_CONNECTING = 0,
    DL_STATE_CONNECTED = 1,
    DL_STATE_DISCONNECTED = 2,
    DL_STATE_FAILED = 3,
} DLState;

typedef enum {
    DL_CERT_REJECT = 0,
    DL_CERT_ACCEPT_ONCE = 2,
} DLCertDecision;

typedef enum {
    DL_MOUSE_LEFT = 0,
    DL_MOUSE_RIGHT = 1,
    DL_MOUSE_MIDDLE = 2,
} DLMouseButton;

/// すべてのコールバックは接続スレッド（メインスレッドではない）から呼ばれる。
typedef struct {
    void *userdata;

    /// 接続状態の変化。error_code は FreeRDP のエラーコード（0 = エラーなし）。
    void (*on_state)(void *userdata, DLState state, uint32_t error_code, const char *message);

    /// リモートデスクトップのサイズが決まった／変わった。
    void (*on_resize)(void *userdata, uint32_t width, uint32_t height);

    /// 画面の一部が更新された。buffer は BGRA32 のフレームバッファ全体で、
    /// コールバック中のみ有効。(x, y, w, h) が更新された範囲。
    void (*on_frame)(void *userdata, const uint8_t *buffer, uint32_t stride,
                     uint32_t width, uint32_t height,
                     int32_t x, int32_t y, int32_t w, int32_t h);

    /// サーバー証明書の確認。ユーザーの判断が出るまでブロックしてよい。
    /// changed は以前と異なる証明書が提示された場合に true。
    DLCertDecision (*on_verify_certificate)(void *userdata, const char *host, uint16_t port,
                                            const char *common_name, const char *subject,
                                            const char *issuer, const char *fingerprint,
                                            bool changed);
} DLCallbacks;

typedef struct {
    const char *host;
    uint16_t port;
    const char *username;
    const char *password;
    const char *domain;          // NULL または空文字なら未指定
    uint32_t width;
    uint32_t height;
    uint32_t keyboard_layout;    // 例: 0x00000409 (US), 0x00000411 (日本語)
    uint32_t keyboard_type;      // 4 = 101/102キー, 7 = 日本語キーボード
    uint32_t keyboard_subtype;   // 日本語(106/109)なら 2
    uint32_t keyboard_function_keys; // 通常 12
    bool use_nla;                // ネットワークレベル認証
} DLConnectConfig;

DLSession *dl_session_new(const DLCallbacks *callbacks);

/// 接続スレッドを起動する。config の文字列はこの関数内でコピーされる。
bool dl_session_start(DLSession *session, const DLConnectConfig *config);

/// 接続を中断し、接続スレッドの終了を待つ（ブロックする）。
/// on_verify_certificate でブロック中のコールバックは、先に解除しておくこと。
void dl_session_stop(DLSession *session);

void dl_session_free(DLSession *session);

// ---- 入力（任意のスレッドから呼べる。内部キューを経由して接続スレッドで送信される）----

void dl_send_mouse_move(DLSession *session, uint16_t x, uint16_t y);
void dl_send_mouse_button(DLSession *session, DLMouseButton button, bool down, uint16_t x, uint16_t y);
/// delta: 正 = 上（または右）方向。1ノッチ = 120。
void dl_send_mouse_wheel(DLSession *session, int16_t delta, bool horizontal, uint16_t x, uint16_t y);
/// scancode: セット1スキャンコード。拡張キーは 0x100 を付与（例: 右矢印 = 0x14D）。
void dl_send_key(DLSession *session, uint16_t scancode, bool down);
/// UTF-16 コードユニットを1つ送る。
void dl_send_unicode(DLSession *session, uint16_t code_unit, bool down);

/// 認証エラー（ユーザー名・パスワードの誤りなど）かどうか。
bool dl_error_is_auth_failure(uint32_t error_code);

#ifdef __cplusplus
}
#endif

#endif /* DL_SESSION_H */
