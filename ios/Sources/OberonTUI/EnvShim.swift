// EnvShim — @_cdecl entry points for the Env runtime module.
//
// iOS apps have no argv (Env.ArgCount/Arg are stubbed in
// runtime/ios/Env_rt.c). Cwd and BasePath are the two host-driven
// values:
//
//   Cwd      → app's working directory inside its sandbox. For a
//              filestore-backed app the natural choice is the
//              ubiquity container's Documents directory; the host
//              app should call `setCwd(_:)` once at startup to
//              choose it.
//
//   BasePath → project root within the filestore. Defaults to ""
//              (meaning the filestore root itself). The host app
//              calls `setBasePath(_:)` after the user opens a project.
//
// Both are read into Oberon-owned buffers via fixed-length C
// strings; we copy at most `out_len - 1` bytes and NUL-terminate.

import Foundation

@MainActor
public enum Env {
    public static var cwd: String      = ""
    public static var basePath: String = ""

    public static func setCwd(_ path: String)      { cwd = path }
    public static func setBasePath(_ path: String) { basePath = path }
}

@_cdecl("ios_env_cwd")
public func ios_env_cwd(_ out: UnsafeMutablePointer<CChar>?, _ outLen: Int32) {
    MainActor.assumeIsolated { copyCString(Env.cwd, into: out, capacity: outLen) }
}

@_cdecl("ios_env_base_path")
public func ios_env_base_path(_ out: UnsafeMutablePointer<CChar>?, _ outLen: Int32) {
    MainActor.assumeIsolated { copyCString(Env.basePath, into: out, capacity: outLen) }
}

private func copyCString(_ src: String,
                         into out: UnsafeMutablePointer<CChar>?,
                         capacity: Int32) {
    guard let out = out, capacity > 0 else { return }
    out[0] = 0
    src.withCString { p in
        let n = strnlen(p, Int(capacity) - 1)
        memcpy(out, p, n)
        out[n] = 0
    }
}
