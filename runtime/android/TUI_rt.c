/* runtime/android/TUI_rt.c — Android TUI runtime forwarding to
 * Kotlin @JvmStatic methods on com.oneav.oberon.tui.OberonBridge via
 * JNI.
 *
 * The Kotlin bridge in oc/android/ implements this contract:
 *
 *   package com.oneav.oberon.tui
 *   object OberonBridge {
 *     @JvmStatic fun tuiInit(): Unit
 *     @JvmStatic fun tuiShutdown(): Unit
 *     @JvmStatic fun tuiRows(): Int
 *     @JvmStatic fun tuiCols(): Int
 *     @JvmStatic fun tuiClear(): Unit
 *     @JvmStatic fun tuiClearLine(): Unit
 *     @JvmStatic fun tuiMoveTo(col: Int, row: Int): Unit
 *     @JvmStatic fun tuiShowCursor(): Unit
 *     @JvmStatic fun tuiHideCursor(): Unit
 *     @JvmStatic fun tuiSetAttr(attr: Int): Unit
 *     @JvmStatic fun tuiSetFg(color: Int): Unit
 *     @JvmStatic fun tuiSetBg(color: Int): Unit
 *     @JvmStatic fun tuiWriteChar(ch: Int): Unit
 *     @JvmStatic fun tuiWriteStr(bytes: ByteArray, n: Int): Unit
 *     @JvmStatic fun tuiFlush(): Unit
 *     @JvmStatic fun tuiReadKey(): Int
 *   }
 *
 * We cache the class + methodIDs on first use rather than JNI_OnLoad
 * so this file can be a drop-in include in a larger .so without
 * fighting for the OnLoad slot. */

#include <jni.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern JavaVM *g_vm;   /* set in runtime_android.c's JNI_OnLoad */

/* Exported Oberon variables — declared in TUI.Mod, defined by the
 * compiler. */
extern int TUI__Rows;
extern int TUI__Cols;

static jclass    g_cls        = NULL;
static jmethodID mid_init     = NULL;
static jmethodID mid_shutdown = NULL;
static jmethodID mid_rows     = NULL;
static jmethodID mid_cols     = NULL;
static jmethodID mid_clear    = NULL;
static jmethodID mid_clr_line = NULL;
static jmethodID mid_move_to  = NULL;
static jmethodID mid_show_cur = NULL;
static jmethodID mid_hide_cur = NULL;
static jmethodID mid_set_attr = NULL;
static jmethodID mid_set_fg   = NULL;
static jmethodID mid_set_bg   = NULL;
static jmethodID mid_wr_char  = NULL;
static jmethodID mid_wr_str   = NULL;
static jmethodID mid_flush    = NULL;
static jmethodID mid_read_key = NULL;

static JNIEnv *get_env(void) {
    JNIEnv *env = NULL;
    if (!g_vm) return NULL;
    jint rc = (*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        (*g_vm)->AttachCurrentThread(g_vm, &env, NULL);
    }
    return env;
}

static void ensure_bindings(JNIEnv *env) {
    if (g_cls) return;
    jclass local = (*env)->FindClass(env, "com/oneav/oberon/tui/OberonBridge");
    if (!local) return;
    g_cls        = (jclass)(*env)->NewGlobalRef(env, local);
    mid_init     = (*env)->GetStaticMethodID(env, g_cls, "tuiInit",       "()V");
    mid_shutdown = (*env)->GetStaticMethodID(env, g_cls, "tuiShutdown",   "()V");
    mid_rows     = (*env)->GetStaticMethodID(env, g_cls, "tuiRows",       "()I");
    mid_cols     = (*env)->GetStaticMethodID(env, g_cls, "tuiCols",       "()I");
    mid_clear    = (*env)->GetStaticMethodID(env, g_cls, "tuiClear",      "()V");
    mid_clr_line = (*env)->GetStaticMethodID(env, g_cls, "tuiClearLine",  "()V");
    mid_move_to  = (*env)->GetStaticMethodID(env, g_cls, "tuiMoveTo",     "(II)V");
    mid_show_cur = (*env)->GetStaticMethodID(env, g_cls, "tuiShowCursor", "()V");
    mid_hide_cur = (*env)->GetStaticMethodID(env, g_cls, "tuiHideCursor", "()V");
    mid_set_attr = (*env)->GetStaticMethodID(env, g_cls, "tuiSetAttr",    "(I)V");
    mid_set_fg   = (*env)->GetStaticMethodID(env, g_cls, "tuiSetFg",      "(I)V");
    mid_set_bg   = (*env)->GetStaticMethodID(env, g_cls, "tuiSetBg",      "(I)V");
    mid_wr_char  = (*env)->GetStaticMethodID(env, g_cls, "tuiWriteChar",  "(I)V");
    mid_wr_str   = (*env)->GetStaticMethodID(env, g_cls, "tuiWriteStr",   "([BI)V");
    mid_flush    = (*env)->GetStaticMethodID(env, g_cls, "tuiFlush",      "()V");
    mid_read_key = (*env)->GetStaticMethodID(env, g_cls, "tuiReadKey",    "()I");
}

static void refresh_dims(JNIEnv *env) {
    TUI__Rows = (int)(*env)->CallStaticIntMethod(env, g_cls, mid_rows);
    TUI__Cols = (int)(*env)->CallStaticIntMethod(env, g_cls, mid_cols);
}

/* ---------- Oberon-facing entry points ---------- */

void TUI__Init(void) {
    JNIEnv *env = get_env(); if (!env) return;
    ensure_bindings(env);    if (!g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_init);
    refresh_dims(env);
}

void TUI__Shutdown(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_shutdown);
}

void TUI__Resize(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    refresh_dims(env);
}

void TUI__Clear(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_clear);
}

void TUI__ClearLine(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_clr_line);
}

void TUI__MoveTo(int col, int row) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_move_to, (jint)col, (jint)row);
}

void TUI__ShowCursor(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_show_cur);
}

void TUI__HideCursor(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_hide_cur);
}

void TUI__SetAttr(int attr) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_set_attr, (jint)attr);
}

void TUI__SetFg(int color) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_set_fg, (jint)color);
}

void TUI__SetBg(int color) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_set_bg, (jint)color);
}

void TUI__Write(char ch) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_wr_char, (jint)(unsigned char)ch);
}

void TUI__WriteStr(const char *s, int n) {
    JNIEnv *env = get_env(); if (!env || !g_cls || n <= 0) return;
    jbyteArray arr = (*env)->NewByteArray(env, n);
    if (!arr) return;
    (*env)->SetByteArrayRegion(env, arr, 0, n, (const jbyte *)s);
    (*env)->CallStaticVoidMethod(env, g_cls, mid_wr_str, arr, (jint)n);
    (*env)->DeleteLocalRef(env, arr);
}

/* Local itoa saves a JNI round-trip per digit. */
static void write_uint(unsigned x) {
    char buf[12];
    int i = 0;
    if (x == 0) { TUI__Write('0'); return; }
    while (x > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (x % 10));
        x /= 10;
    }
    while (i > 0) TUI__Write(buf[--i]);
}

void TUI__WriteInt(int x) {
    if (x < 0) {
        TUI__Write('-');
        write_uint((unsigned)(-(long)x));
    } else {
        write_uint((unsigned)x);
    }
}

void TUI__Flush(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_flush);
}

int TUI__ReadKey(void) {
    JNIEnv *env = get_env(); if (!env || !g_cls) return 0;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_flush);
    return (int)(*env)->CallStaticIntMethod(env, g_cls, mid_read_key);
}

/* Event-driven key dispatch: Kotlin's input handler calls
 * oc_dispatch_key(code) on each key event; we invoke the registered
 * Oberon handler. */
static void (*key_handler)(int) = NULL;

void TUI__SetKeyHandler(void (*h)(int)) {
    key_handler = h;
}

void TUI__Run(void) {
    /* No loop — Kotlin drives per-event dispatch. */
}

void TUI__Quit(void) {
    key_handler = NULL;
    TUI__Shutdown();
}

/* Exported for the Kotlin bridge to call via JNI. Naming:
 *   package com.oneav.oberon.tui
 *   external fun ocDispatchKey(code: Int)
 * declared inside an object OberonBridge maps to
 *   Java_com_oneav_oberon_tui_OberonBridge_ocDispatchKey
 * with (JNIEnv*, jobject, jint) — jobject is the Kotlin object
 * instance and we ignore it. */
JNIEXPORT void JNICALL
Java_com_oneav_oberon_tui_OberonBridge_ocDispatchKey(JNIEnv *env,
                                                     jobject thiz,
                                                     jint code) {
    (void)env; (void)thiz;
    if (key_handler) key_handler((int)code);
}

void TUI__init(void) {
    /* Don't auto-Init() — host program (Oed__init via Kotlin's
     * onCreate → Oed__init call) decides when to switch into TUI
     * mode. Matches posix / wasm / ios. */
}
