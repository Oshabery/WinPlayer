#include "DLSession.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include <winpr/synch.h>
#include <winpr/wtypes.h>

#include <freerdp/client.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/error.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>

// ------------------------------------------------------------------------------------------
// 入力キュー
// ------------------------------------------------------------------------------------------

typedef enum {
    DL_EVT_MOUSE = 0,
    DL_EVT_KEY = 1,
    DL_EVT_UNICODE = 2,
} DLEventKind;

typedef struct {
    uint8_t kind;
    uint16_t flags; // MOUSE: ポインタフラグ / KEY: 押下=1 / UNICODE: キーボードフラグ
    uint16_t a;     // MOUSE: x / KEY: スキャンコード / UNICODE: コードユニット
    uint16_t b;     // MOUSE: y
} DLInputEvent;

#define DL_QUEUE_CAPACITY 1024

struct DLSession {
    DLCallbacks callbacks;

    freerdp *instance;
    rdpContext *context;

    pthread_t thread;
    bool thread_running;
    volatile bool stopping; // dl_session_stop による中断中

    pthread_mutex_t queue_lock;
    DLInputEvent queue[DL_QUEUE_CAPACITY];
    size_t queue_head;
    size_t queue_count;
    HANDLE wake_event;
};

typedef struct {
    rdpClientContext common; // 先頭に置くこと（FreeRDPの規約）
    DLSession *session;
} DLContext;

static DLSession *dl_session_from_context(rdpContext *context) {
    return context ? ((DLContext *)context)->session : NULL;
}

static void dl_enqueue(DLSession *s, DLInputEvent ev) {
    if (!s) return;
    pthread_mutex_lock(&s->queue_lock);

    // 連続するマウス移動はまとめる（キューがあふれないように）
    if (ev.kind == DL_EVT_MOUSE && ev.flags == PTR_FLAGS_MOVE && s->queue_count > 0) {
        size_t last = (s->queue_head + s->queue_count - 1) % DL_QUEUE_CAPACITY;
        DLInputEvent *prev = &s->queue[last];
        if (prev->kind == DL_EVT_MOUSE && prev->flags == PTR_FLAGS_MOVE) {
            *prev = ev;
            pthread_mutex_unlock(&s->queue_lock);
            return;
        }
    }

    if (s->queue_count < DL_QUEUE_CAPACITY) {
        size_t tail = (s->queue_head + s->queue_count) % DL_QUEUE_CAPACITY;
        s->queue[tail] = ev;
        s->queue_count++;
    }
    pthread_mutex_unlock(&s->queue_lock);

    if (s->wake_event) SetEvent(s->wake_event);
}

static BOOL dl_drain_input(DLSession *s) {
    DLInputEvent batch[DL_QUEUE_CAPACITY];
    size_t n = 0;

    pthread_mutex_lock(&s->queue_lock);
    while (s->queue_count > 0) {
        batch[n++] = s->queue[s->queue_head];
        s->queue_head = (s->queue_head + 1) % DL_QUEUE_CAPACITY;
        s->queue_count--;
    }
    pthread_mutex_unlock(&s->queue_lock);

    rdpInput *input = s->context->input;
    for (size_t i = 0; i < n; i++) {
        const DLInputEvent *ev = &batch[i];
        BOOL ok = TRUE;
        switch (ev->kind) {
            case DL_EVT_MOUSE:
                ok = freerdp_input_send_mouse_event(input, ev->flags, ev->a, ev->b);
                break;
            case DL_EVT_KEY:
                ok = freerdp_input_send_keyboard_event_ex(input, ev->flags != 0, FALSE, ev->a);
                break;
            case DL_EVT_UNICODE:
                ok = freerdp_input_send_unicode_keyboard_event(input, ev->flags, ev->a);
                break;
            default:
                break;
        }
        if (!ok) return FALSE;
    }
    return TRUE;
}

// ------------------------------------------------------------------------------------------
// 描画コールバック
// ------------------------------------------------------------------------------------------

static void dl_notify_resize(DLSession *s) {
    rdpGdi *gdi = s->context->gdi;
    if (s->callbacks.on_resize && gdi) {
        s->callbacks.on_resize(s->callbacks.userdata, gdi->width, gdi->height);
    }
}

static BOOL dl_begin_paint(rdpContext *context) {
    rdpGdi *gdi = context->gdi;
    if (!gdi || !gdi->primary || !gdi->primary->hdc || !gdi->primary->hdc->hwnd) return FALSE;
    HGDI_WND hwnd = gdi->primary->hdc->hwnd;
    if (!hwnd->invalid) return FALSE;
    hwnd->invalid->null = TRUE;
    hwnd->ninvalid = 0;
    return TRUE;
}

static BOOL dl_end_paint(rdpContext *context) {
    DLSession *s = dl_session_from_context(context);
    rdpGdi *gdi = context->gdi;
    if (!s || !gdi || !gdi->primary || !gdi->primary->hdc || !gdi->primary->hdc->hwnd) return FALSE;

    HGDI_WND hwnd = gdi->primary->hdc->hwnd;
    if (!hwnd->invalid || hwnd->invalid->null) return TRUE;

    const INT32 x = hwnd->invalid->x;
    const INT32 y = hwnd->invalid->y;
    const INT32 w = hwnd->invalid->w;
    const INT32 h = hwnd->invalid->h;

    if (s->callbacks.on_frame && w > 0 && h > 0) {
        s->callbacks.on_frame(s->callbacks.userdata, gdi->primary_buffer, gdi->stride,
                              gdi->width, gdi->height, x, y, w, h);
    }

    hwnd->invalid->null = TRUE;
    hwnd->ninvalid = 0;
    return TRUE;
}

static BOOL dl_desktop_resize(rdpContext *context) {
    DLSession *s = dl_session_from_context(context);
    rdpSettings *settings = context->settings;
    if (!s || !context->gdi) return FALSE;

    if (!gdi_resize(context->gdi,
                    freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth),
                    freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight))) {
        return FALSE;
    }
    dl_notify_resize(s);
    return TRUE;
}

// ------------------------------------------------------------------------------------------
// 接続ライフサイクル
// ------------------------------------------------------------------------------------------

static BOOL dl_pre_connect(freerdp *instance) {
    rdpSettings *settings = instance->context->settings;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_OsMajorType, OSMAJORTYPE_IOS)) return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_OsMinorType, OSMINORTYPE_UNSPECIFIED)) return FALSE;
    return TRUE;
}

static BOOL dl_post_connect(freerdp *instance) {
    rdpContext *context = instance->context;
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32)) return FALSE;

    context->update->BeginPaint = dl_begin_paint;
    context->update->EndPaint = dl_end_paint;
    context->update->DesktopResize = dl_desktop_resize;

    dl_notify_resize(dl_session_from_context(context));
    return TRUE;
}

static void dl_post_disconnect(freerdp *instance) {
    if (instance && instance->context) gdi_free(instance);
}

static BOOL dl_authenticate_ex(freerdp *instance, char **username, char **password, char **domain,
                               rdp_auth_reason reason) {
    (void)instance;
    (void)username;
    (void)domain;
    (void)reason;
    // 資格情報は接続前にアプリ側で設定済み。不足していれば失敗させ、アプリ側で再入力させる。
    return password && *password && **password;
}

static DWORD dl_verify_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                      const char *common_name, const char *subject,
                                      const char *issuer, const char *fingerprint, DWORD flags) {
    (void)flags;
    DLSession *s = dl_session_from_context(instance->context);
    if (!s || !s->callbacks.on_verify_certificate) return DL_CERT_REJECT;
    return (DWORD)s->callbacks.on_verify_certificate(s->callbacks.userdata, host, port, common_name,
                                                     subject, issuer, fingerprint, false);
}

static DWORD dl_verify_changed_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                              const char *common_name, const char *subject,
                                              const char *issuer, const char *new_fingerprint,
                                              const char *old_subject, const char *old_issuer,
                                              const char *old_fingerprint, DWORD flags) {
    (void)old_subject;
    (void)old_issuer;
    (void)old_fingerprint;
    (void)flags;
    DLSession *s = dl_session_from_context(instance->context);
    if (!s || !s->callbacks.on_verify_certificate) return DL_CERT_REJECT;
    return (DWORD)s->callbacks.on_verify_certificate(s->callbacks.userdata, host, port, common_name,
                                                     subject, issuer, new_fingerprint, true);
}

static BOOL dl_client_new(freerdp *instance, rdpContext *context) {
    (void)context;
    instance->PreConnect = dl_pre_connect;
    instance->PostConnect = dl_post_connect;
    instance->PostDisconnect = dl_post_disconnect;
    instance->AuthenticateEx = dl_authenticate_ex;
    instance->VerifyCertificateEx = dl_verify_certificate_ex;
    instance->VerifyChangedCertificateEx = dl_verify_changed_certificate_ex;
    return TRUE;
}

static void dl_client_free(freerdp *instance, rdpContext *context) {
    (void)instance;
    (void)context;
}

static int dl_client_start(rdpContext *context) {
    (void)context;
    return 0;
}

static int dl_client_stop(rdpContext *context) {
    (void)context;
    return 0;
}

static void dl_report(DLSession *s, DLState state, UINT32 error) {
    if (!s->callbacks.on_state) return;
    // 利用者による中断で起きたエラーは「切断」として扱う
    if (state == DL_STATE_FAILED && __atomic_load_n(&s->stopping, __ATOMIC_SEQ_CST)) {
        state = DL_STATE_DISCONNECTED;
        error = FREERDP_ERROR_SUCCESS;
    }
    const char *message = (error != FREERDP_ERROR_SUCCESS) ? freerdp_get_last_error_string(error) : NULL;
    s->callbacks.on_state(s->callbacks.userdata, state, error, message);
}

static void *dl_thread_main(void *arg) {
    DLSession *s = (DLSession *)arg;
    freerdp *instance = s->instance;
    rdpContext *context = s->context;

    dl_report(s, DL_STATE_CONNECTING, FREERDP_ERROR_SUCCESS);

    if (!freerdp_connect(instance)) {
        UINT32 error = freerdp_get_last_error(context);
        if (error == FREERDP_ERROR_SUCCESS) error = FREERDP_ERROR_CONNECT_FAILED;
        // 利用者による中断は「切断」として扱う
        if (error == FREERDP_ERROR_CONNECT_CANCELLED) {
            dl_report(s, DL_STATE_DISCONNECTED, FREERDP_ERROR_SUCCESS);
        } else {
            dl_report(s, DL_STATE_FAILED, error);
        }
        return NULL;
    }

    dl_report(s, DL_STATE_CONNECTED, FREERDP_ERROR_SUCCESS);

    UINT32 error = FREERDP_ERROR_SUCCESS;
    while (!freerdp_shall_disconnect_context(context)) {
        HANDLE handles[MAXIMUM_WAIT_OBJECTS] = {0};
        DWORD count = freerdp_get_event_handles(context, handles, ARRAYSIZE(handles) - 1);
        if (count == 0) {
            error = freerdp_get_last_error(context);
            break;
        }
        handles[count++] = s->wake_event;

        DWORD status = WaitForMultipleObjects(count, handles, FALSE, 100);
        if (status == WAIT_FAILED) {
            error = freerdp_get_last_error(context);
            break;
        }

        ResetEvent(s->wake_event);
        if (!dl_drain_input(s)) {
            error = freerdp_get_last_error(context);
            break;
        }

        if (!freerdp_check_event_handles(context)) {
            error = freerdp_get_last_error(context);
            break;
        }
    }

    freerdp_disconnect(instance);

    if (error == FREERDP_ERROR_SUCCESS || error == FREERDP_ERROR_CONNECT_CANCELLED) {
        dl_report(s, DL_STATE_DISCONNECTED, FREERDP_ERROR_SUCCESS);
    } else {
        dl_report(s, DL_STATE_FAILED, error);
    }
    return NULL;
}

// ------------------------------------------------------------------------------------------
// 公開API
// ------------------------------------------------------------------------------------------

DLSession *dl_session_new(const DLCallbacks *callbacks) {
    DLSession *s = calloc(1, sizeof(DLSession));
    if (!s) return NULL;
    if (callbacks) s->callbacks = *callbacks;
    pthread_mutex_init(&s->queue_lock, NULL);

    // WinPR は auto-reset イベント未対応のため manual-reset にし、待機後に ResetEvent する
    s->wake_event = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!s->wake_event) goto fail;

    RDP_CLIENT_ENTRY_POINTS ep = {0};
    ep.Size = sizeof(RDP_CLIENT_ENTRY_POINTS);
    ep.Version = RDP_CLIENT_INTERFACE_VERSION;
    ep.ContextSize = sizeof(DLContext);
    ep.ClientNew = dl_client_new;
    ep.ClientFree = dl_client_free;
    ep.ClientStart = dl_client_start;
    ep.ClientStop = dl_client_stop;

    s->context = freerdp_client_context_new(&ep);
    if (!s->context) goto fail;
    ((DLContext *)s->context)->session = s;
    s->instance = s->context->instance;
    return s;

fail:
    dl_session_free(s);
    return NULL;
}

static bool dl_set_string(rdpSettings *settings, FreeRDP_Settings_Keys_String key, const char *value) {
    if (!value || !*value) return true;
    return freerdp_settings_set_string(settings, key, value);
}

bool dl_session_start(DLSession *s, const DLConnectConfig *c) {
    if (!s || !c || !c->host || s->thread_running) return false;
    rdpSettings *settings = s->context->settings;

    bool ok = true;
    ok = ok && freerdp_settings_set_string(settings, FreeRDP_ServerHostname, c->host);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, c->port ? c->port : 3389);
    ok = ok && dl_set_string(settings, FreeRDP_Username, c->username);
    ok = ok && dl_set_string(settings, FreeRDP_Password, c->password);
    ok = ok && dl_set_string(settings, FreeRDP_Domain, c->domain);
    ok = ok && freerdp_settings_set_string(settings, FreeRDP_ClientHostname, "DeskLink-iPad");

    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, c->width);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, c->height);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE);

    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, c->use_nla);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, !c->use_nla);

    if (c->keyboard_layout) {
        ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_KeyboardLayout, c->keyboard_layout);
    }
    if (c->keyboard_type) {
        ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_KeyboardType, c->keyboard_type);
        ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_KeyboardSubType, c->keyboard_subtype);
        ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_KeyboardFunctionKey,
                                               c->keyboard_function_keys ? c->keyboard_function_keys : 12);
    }

    // MVP では音声・デバイス・クリップボードのチャネルは使わない（未ビルドのチャネルを読み込ませない）
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AudioPlayback, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AudioCapture, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_DeviceRedirection, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectClipboard, FALSE);

    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AutoReconnectionEnabled, TRUE);
    ok = ok && freerdp_set_connection_type(settings, CONNECTION_TYPE_BROADBAND_HIGH);
    if (!ok) return false;

    if (pthread_create(&s->thread, NULL, dl_thread_main, s) != 0) return false;
    s->thread_running = true;
    return true;
}

void dl_session_stop(DLSession *s) {
    if (!s || !s->thread_running) return;
    __atomic_store_n(&s->stopping, true, __ATOMIC_SEQ_CST);
    freerdp_abort_connect_context(s->context);
    if (s->wake_event) SetEvent(s->wake_event);
    pthread_join(s->thread, NULL);
    s->thread_running = false;
    __atomic_store_n(&s->stopping, false, __ATOMIC_SEQ_CST);
}

void dl_session_free(DLSession *s) {
    if (!s) return;
    dl_session_stop(s);
    if (s->context) freerdp_client_context_free(s->context);
    if (s->wake_event) CloseHandle(s->wake_event);
    pthread_mutex_destroy(&s->queue_lock);
    free(s);
}

void dl_send_mouse_move(DLSession *s, uint16_t x, uint16_t y) {
    dl_enqueue(s, (DLInputEvent){ .kind = DL_EVT_MOUSE, .flags = PTR_FLAGS_MOVE, .a = x, .b = y });
}

void dl_send_mouse_button(DLSession *s, DLMouseButton button, bool down, uint16_t x, uint16_t y) {
    uint16_t flags = 0;
    switch (button) {
        case DL_MOUSE_LEFT: flags = PTR_FLAGS_BUTTON1; break;
        case DL_MOUSE_RIGHT: flags = PTR_FLAGS_BUTTON2; break;
        case DL_MOUSE_MIDDLE: flags = PTR_FLAGS_BUTTON3; break;
    }
    if (down) flags |= PTR_FLAGS_DOWN;
    dl_enqueue(s, (DLInputEvent){ .kind = DL_EVT_MOUSE, .flags = flags, .a = x, .b = y });
}

void dl_send_mouse_wheel(DLSession *s, int16_t delta, bool horizontal, uint16_t x, uint16_t y) {
    if (delta == 0) return;
    // ホイール量は9ビットの2の補数で表す（-256〜255）
    if (delta > 255) delta = 255;
    if (delta < -256) delta = -256;
    uint16_t flags = horizontal ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;
    if (delta < 0) flags |= PTR_FLAGS_WHEEL_NEGATIVE;
    flags |= (uint16_t)delta & WheelRotationMask;
    dl_enqueue(s, (DLInputEvent){ .kind = DL_EVT_MOUSE, .flags = flags, .a = x, .b = y });
}

void dl_send_key(DLSession *s, uint16_t scancode, bool down) {
    dl_enqueue(s, (DLInputEvent){ .kind = DL_EVT_KEY, .flags = down ? 1 : 0, .a = scancode });
}

void dl_send_unicode(DLSession *s, uint16_t code_unit, bool down) {
    dl_enqueue(s, (DLInputEvent){ .kind = DL_EVT_UNICODE, .flags = down ? 0 : KBD_FLAGS_RELEASE, .a = code_unit });
}

bool dl_error_is_auth_failure(uint32_t error_code) {
    switch (error_code) {
        case FREERDP_ERROR_AUTHENTICATION_FAILED:
        case FREERDP_ERROR_CONNECT_LOGON_FAILURE:
        case FREERDP_ERROR_CONNECT_WRONG_PASSWORD:
        case FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS:
        case FREERDP_ERROR_CONNECT_ACCESS_DENIED:
        case FREERDP_ERROR_CONNECT_ACCOUNT_RESTRICTION:
        case FREERDP_ERROR_CONNECT_PASSWORD_EXPIRED:
        case FREERDP_ERROR_CONNECT_PASSWORD_CERTAINLY_EXPIRED:
        case FREERDP_ERROR_CONNECT_PASSWORD_MUST_CHANGE:
            return true;
        default:
            return false;
    }
}
