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
import UIKit

@MainActor
public enum Env {
    public static var cwd: String      = ""
    public static var basePath: String = ""

    public static func setCwd(_ path: String)      { cwd = path }
    public static func setBasePath(_ path: String) { basePath = path }

    /// Bind cwd to the app's Documents directory and chdir() the
    /// POSIX-level process working directory there too — the
    /// Files runtime sidecar (runtime/ios/Files_rt.c) is straight
    /// POSIX I/O, so relative paths must resolve under a writable
    /// sandbox location. Documents is the natural choice: it's
    /// writable, persists across launches, and (with
    /// UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace in
    /// Info.plist) shows up in the Files app so the user can drop
    /// files in from iCloud Drive or other apps.
    ///
    /// Call once at App.init, before TerminalView's onReady fires
    /// the Oberon-side bootstrap.
    @discardableResult
    public static func useDocumentsDirectory() -> String {
        let urls = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)
        let path = urls.first?.path ?? NSTemporaryDirectory()
        cwd = path
        _ = path.withCString { chdir($0) }
        return path
    }
}

@_cdecl("ios_env_cwd")
public func ios_env_cwd(_ out: UnsafeMutablePointer<CChar>?, _ outLen: Int32) {
    MainActor.assumeIsolated { copyCString(Env.cwd, into: out, capacity: outLen) }
}

@_cdecl("ios_env_base_path")
public func ios_env_base_path(_ out: UnsafeMutablePointer<CChar>?, _ outLen: Int32) {
    MainActor.assumeIsolated { copyCString(Env.basePath, into: out, capacity: outLen) }
}

/// Open a URL via UIApplication. The Oberon open-array ABI passes
/// (ptr, declared-array-length) — typically 256 for a fixed-size
/// path/URL buffer — and the actual string inside is 0X-terminated,
/// so we have to trim at the first NUL before parsing. Without the
/// trim the String contains lots of trailing NULs and `URL(string:)`
/// returns nil silently.
@_cdecl("ios_env_open_url")
public func ios_env_open_url(_ url: UnsafePointer<CChar>?, _ n: Int32) {
    guard let url = url, n > 0 else { return }
    var actual = 0
    while actual < Int(n) && url[actual] != 0 { actual += 1 }
    guard actual > 0 else { return }
    let bytes = (0..<actual).map { UInt8(bitPattern: url[$0]) }
    guard let str = String(bytes: bytes, encoding: .utf8),
          let parsed = URL(string: str) else { return }
    MainActor.assumeIsolated {
        UIApplication.shared.open(parsed, options: [:]) { _ in }
    }
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
