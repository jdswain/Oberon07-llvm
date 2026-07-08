/* runtime/android/Env_rt.c — Env backend routing to Kotlin.
 *
 * Android apps have no meaningful argv; ArgCount returns 0, Arg
 * returns empty. Cwd is the app's files directory (set by the
 * Kotlin side at startup via chdir + Env bridge). BasePath is
 * empty by default; the host can set it via a Kotlin call.
 * OpenURL hands the URL to Kotlin, which invokes
 * `Intent.ACTION_VIEW` via the shared Activity.
 */

#include <jni.h>
#include <stddef.h>
#include <string.h>

extern JavaVM *g_vm;

static jclass    g_cls        = NULL;
static jmethodID mid_cwd      = NULL;
static jmethodID mid_base     = NULL;
static jmethodID mid_open_url = NULL;

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
    mid_cwd      = (*env)->GetStaticMethodID(env, g_cls, "envCwd",      "()Ljava/lang/String;");
    mid_base     = (*env)->GetStaticMethodID(env, g_cls, "envBasePath", "()Ljava/lang/String;");
    mid_open_url = (*env)->GetStaticMethodID(env, g_cls, "envOpenUrl",  "(Ljava/lang/String;)V");
}

/* Copy a Java String into an Oberon-owned buffer. */
static void copy_jstring(JNIEnv *env, jstring js, char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    if (!js) return;
    const char *s = (*env)->GetStringUTFChars(env, js, NULL);
    if (!s) return;
    size_t n = strlen(s);
    if (n > (size_t)(out_len - 1)) n = (size_t)(out_len - 1);
    memcpy(out, s, n);
    out[n] = 0;
    (*env)->ReleaseStringUTFChars(env, js, s);
}

int Env__ArgCount(void) {
    return 0;
}

void Env__Arg(int i, char *out, int out_len) {
    (void)i;
    if (out_len > 0) out[0] = 0;
}

void Env__Cwd(char *out, int out_len) {
    JNIEnv *env = get_env();
    if (out_len > 0) out[0] = 0;
    if (!env) return;
    ensure_bindings(env);
    if (!g_cls) return;
    jstring js = (jstring)(*env)->CallStaticObjectMethod(env, g_cls, mid_cwd);
    copy_jstring(env, js, out, out_len);
    if (js) (*env)->DeleteLocalRef(env, js);
}

void Env__BasePath(char *out, int out_len) {
    JNIEnv *env = get_env();
    if (out_len > 0) out[0] = 0;
    if (!env) return;
    ensure_bindings(env);
    if (!g_cls) return;
    jstring js = (jstring)(*env)->CallStaticObjectMethod(env, g_cls, mid_base);
    copy_jstring(env, js, out, out_len);
    if (js) (*env)->DeleteLocalRef(env, js);
}

void Env__OpenURL(const char *url, int n) {
    JNIEnv *env = get_env();
    if (!env || !url || n <= 0) return;
    ensure_bindings(env);
    if (!g_cls) return;
    /* Trim at first NUL — Oberon open-array ABI passes declared
     * length, not strlen, so we must not pass trailing NULs into
     * the Java String constructor. */
    int actual = 0;
    while (actual < n && url[actual] != 0) actual++;
    if (actual <= 0) return;
    jbyteArray buf = (*env)->NewByteArray(env, actual);
    if (!buf) return;
    (*env)->SetByteArrayRegion(env, buf, 0, actual, (const jbyte *)url);
    /* Construct Java String from the byte array via UTF-8. */
    jclass strCls = (*env)->FindClass(env, "java/lang/String");
    jmethodID strCtor = (*env)->GetMethodID(env, strCls, "<init>", "([BLjava/lang/String;)V");
    jstring encoding = (*env)->NewStringUTF(env, "UTF-8");
    jstring js = (jstring)(*env)->NewObject(env, strCls, strCtor, buf, encoding);
    (*env)->CallStaticVoidMethod(env, g_cls, mid_open_url, js);
    (*env)->DeleteLocalRef(env, js);
    (*env)->DeleteLocalRef(env, encoding);
    (*env)->DeleteLocalRef(env, strCls);
    (*env)->DeleteLocalRef(env, buf);
}

void Env__init(void) {}
