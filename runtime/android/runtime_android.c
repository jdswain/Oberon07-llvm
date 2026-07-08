/* runtime_android.c — Android-specific runtime glue.
 *
 * Stashes the JavaVM* on JNI_OnLoad so the other sidecars
 * (TUI_rt.c, Out_rt.c, Env_rt.c) can reach up into Kotlin.
 * Also exposes small JNI entry points the Kotlin bridge calls to
 * boot the Oberon side (`ocSetArgs`, and a placeholder `entryInit`
 * the consuming app overrides via a per-app JNI binding).
 *
 * The bulk of the ARC/runtime helpers live in runtime.c which is
 * unchanged from the posix build. */

#include <jni.h>
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

JavaVM *g_vm = NULL;

extern void oc_set_args(int argc, char **argv);

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
Java_com_oneav_oberon_tui_OberonBridge_ocSetArgs(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    /* Android apps have no argv — pass empty like iOS. */
    oc_set_args(0, NULL);
}

/* Set the POSIX process working directory. Called by the Activity
 * before Oed__init runs so the Files runtime (open/read/write with
 * relative paths) resolves under a writable sandbox location. */
JNIEXPORT void JNICALL
Java_com_oneav_oberon_tui_OberonBridge_ocChdir(JNIEnv *env, jobject thiz, jstring path) {
    (void)thiz;
    if (!path) return;
    const char *p = (*env)->GetStringUTFChars(env, path, NULL);
    if (!p) return;
    (void)chdir(p);
    (*env)->ReleaseStringUTFChars(env, path, p);
}
