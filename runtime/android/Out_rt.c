/* runtime/android/Out_rt.c — routes Out.* to the same Kotlin
 * bridge as TUI: on-device Out has nowhere to go but the terminal
 * view (there is no stdout the user sees), and unified writes
 * match the iOS host. */

#include <jni.h>
#include <stddef.h>

extern JavaVM *g_vm;

static jclass    g_cls        = NULL;
static jmethodID mid_wr_char  = NULL;
static jmethodID mid_wr_str   = NULL;
static jmethodID mid_wr_int   = NULL;
static jmethodID mid_ln       = NULL;

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
    mid_wr_char  = (*env)->GetStaticMethodID(env, g_cls, "outWriteChar", "(I)V");
    mid_wr_str   = (*env)->GetStaticMethodID(env, g_cls, "outWriteStr",  "([BI)V");
    mid_wr_int   = (*env)->GetStaticMethodID(env, g_cls, "outWriteInt",  "(I)V");
    mid_ln       = (*env)->GetStaticMethodID(env, g_cls, "outLn",        "()V");
}

void Out__Write(char ch) {
    JNIEnv *env = get_env(); if (!env) return;
    ensure_bindings(env);    if (!g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_wr_char, (jint)(unsigned char)ch);
}

void Out__WriteString(const char *s, int n) {
    JNIEnv *env = get_env(); if (!env) return;
    ensure_bindings(env);    if (!g_cls || n <= 0) return;
    jbyteArray arr = (*env)->NewByteArray(env, n);
    if (!arr) return;
    (*env)->SetByteArrayRegion(env, arr, 0, n, (const jbyte *)s);
    (*env)->CallStaticVoidMethod(env, g_cls, mid_wr_str, arr, (jint)n);
    (*env)->DeleteLocalRef(env, arr);
}

void Out__WriteInt(int x) {
    JNIEnv *env = get_env(); if (!env) return;
    ensure_bindings(env);    if (!g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_wr_int, (jint)x);
}

void Out__Ln(void) {
    JNIEnv *env = get_env(); if (!env) return;
    ensure_bindings(env);    if (!g_cls) return;
    (*env)->CallStaticVoidMethod(env, g_cls, mid_ln);
}

void Out__init(void) {}
