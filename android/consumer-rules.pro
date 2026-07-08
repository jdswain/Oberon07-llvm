# Keep the OberonBridge object and every @JvmStatic method on it —
# the native runtime sidecars in runtime/android/*_rt.c find these
# via reflection (FindClass / GetStaticMethodID) and would break
# silently under R8 shrinking otherwise.
-keep class com.oneav.oberon.tui.OberonBridge {
    public static <methods>;
    public *;
}
-keepclasseswithmembernames class com.oneav.oberon.tui.OberonBridge {
    native <methods>;
}
