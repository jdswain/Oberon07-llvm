// oc-server — HTTP server pairing with the Oberon web port.
//
// Two responsibilities:
//
//   1. Serve the static web app (HTML, JS, wasm) under "/".
//      Defaults to ../web/dist and ../web/index.html.
//
//   2. Expose a small file API under /api/files/<projectBase>/<path>
//      that the Files shim drives via synchronous XHR. Everything is
//      rooted at a FileStore directory; paths that resolve outside it
//      are rejected.
//
// All paths are filepath.Clean'd and verified against the FileStore
// root via filepath.Rel — anything starting with ".." after that gets
// 403 Forbidden. No symlink-following is enabled.
package main

import (
	"errors"
	"flag"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

type config struct {
	addr      string
	webDir    string // contains index.html and dist/
	wasmDir   string // contains app.wasm
	fileStore string // root of /api/files
}

func main() {
	cfg := config{}
	flag.StringVar(&cfg.addr,      "addr",       ":8080",      "listen address")
	flag.StringVar(&cfg.webDir,    "web",        "../web",     "static web app dir")
	flag.StringVar(&cfg.wasmDir,   "wasm",       "../web",     "directory containing app.wasm")
	flag.StringVar(&cfg.fileStore, "store",      "./store",    "FileStore root")
	flag.Parse()

	if err := os.MkdirAll(cfg.fileStore, 0755); err != nil {
		log.Fatalf("create store: %v", err)
	}
	abs, err := filepath.Abs(cfg.fileStore)
	if err != nil {
		log.Fatalf("resolve store: %v", err)
	}
	cfg.fileStore = abs

	mux := http.NewServeMux()
	mux.Handle("/api/files/", &filesHandler{root: cfg.fileStore})
	mux.HandleFunc("/api/env/", envHandler)
	mux.Handle("/", staticHandler(cfg.webDir, cfg.wasmDir))

	log.Printf("oc-server: listening on %s", cfg.addr)
	log.Printf("  web dir   = %s", cfg.webDir)
	log.Printf("  wasm dir  = %s", cfg.wasmDir)
	log.Printf("  filestore = %s", cfg.fileStore)
	if err := http.ListenAndServe(cfg.addr, mux); err != nil {
		log.Fatalf("listen: %v", err)
	}
}

// ---- static -----------------------------------------------------

// staticHandler serves the web/ root with two tweaks: /app.wasm
// (and any sibling .wasm) comes from wasmDir if separate, and we set
// the right MIME types because Go's stdlib doesn't know .wasm yet on
// every platform.
func staticHandler(webDir, wasmDir string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clean := path.Clean(r.URL.Path)
		if clean == "/" {
			clean = "/index.html"
		}
		// .wasm files live in wasmDir.
		var fsPath string
		if strings.HasSuffix(clean, ".wasm") {
			fsPath = filepath.Join(wasmDir, clean)
			w.Header().Set("Content-Type", "application/wasm")
		} else {
			fsPath = filepath.Join(webDir, clean)
			switch filepath.Ext(clean) {
			case ".js":    w.Header().Set("Content-Type", "application/javascript")
			case ".css":   w.Header().Set("Content-Type", "text/css")
			case ".html":  w.Header().Set("Content-Type", "text/html; charset=utf-8")
			case ".map":   w.Header().Set("Content-Type", "application/json")
			case ".ttf":   w.Header().Set("Content-Type", "font/ttf")
			case ".otf":   w.Header().Set("Content-Type", "font/otf")
			case ".woff":  w.Header().Set("Content-Type", "font/woff")
			case ".woff2": w.Header().Set("Content-Type", "font/woff2")
			}
		}
		http.ServeFile(w, r, fsPath)
	})
}

// ---- env --------------------------------------------------------

// /api/env/<projectBase> — currently unused by the wasm side (the
// JS env-shim reads window.location directly), but provided as the
// "values come from server and URL" entry point in the design doc.
// Returns a JSON object {projectBase}. Anything richer (env vars,
// auth tokens) can be added here without changing the wasm ABI.
func envHandler(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/api/env/")
	rel = path.Clean("/" + rel)
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"projectBase": "` + rel[1:] + `"}`))
}

// ---- files ------------------------------------------------------

type filesHandler struct {
	root string // absolute, already realpath'd
}

// resolve maps "/api/files/<...>" to an absolute path inside the
// FileStore root. Returns an error if the resolved path escapes the
// root. The caller has already stripped the URL prefix.
func (h *filesHandler) resolve(rel string) (string, error) {
	// Strip any leading slash so filepath.Join keeps us under root.
	cleaned := path.Clean("/" + rel)
	abs := filepath.Join(h.root, cleaned)
	// Re-check via filepath.Rel — if rel starts with ".." we
	// escaped. Symlinks are not resolved; tighten with EvalSymlinks
	// + Rel if needed.
	relCheck, err := filepath.Rel(h.root, abs)
	if err != nil {
		return "", err
	}
	if relCheck == ".." || strings.HasPrefix(relCheck, ".."+string(filepath.Separator)) {
		return "", errors.New("path escapes FileStore")
	}
	return abs, nil
}

func (h *filesHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/api/files/")
	abs, err := h.resolve(rel)
	if err != nil {
		http.Error(w, "forbidden: "+err.Error(), http.StatusForbidden)
		return
	}

	switch r.Method {
	case http.MethodGet:
		if r.URL.Query().Get("list") != "" {
			h.list(w, r, abs)
			return
		}
		h.read(w, r, abs)
	case http.MethodPut:
		h.write(w, r, abs)
	case http.MethodDelete:
		h.delete(w, r, abs)
	case http.MethodHead:
		h.head(w, r, abs)
	case http.MethodPost:
		// rename and mkdir multiplex onto POST via query params
		// because that's what the JS shim emits.
		if newName := r.URL.Query().Get("rename"); newName != "" {
			h.rename(w, r, abs, newName)
			return
		}
		if r.URL.Query().Get("mkdir") != "" {
			h.mkdir(w, r, abs)
			return
		}
		http.Error(w, "POST requires ?rename or ?mkdir", http.StatusBadRequest)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// list emits the directory's entries as plain text, one per line:
//   <name>\t<D|F>\n
// "." and ".." are filtered. The wasm Files shim parses this on
// open_dir and replays it through next_entry / close_dir.
func (h *filesHandler) list(w http.ResponseWriter, r *http.Request, abs string) {
	st, err := os.Stat(abs)
	if errors.Is(err, os.ErrNotExist) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if !st.IsDir() {
		http.Error(w, "not a directory", http.StatusBadRequest)
		return
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	for _, e := range entries {
		name := e.Name()
		if name == "." || name == ".." {
			continue
		}
		// e.IsDir() uses lstat → symlinks to dirs (e.g. /tmp on macOS)
		// would be reported as files. Fall through to stat() so the
		// link target's type wins.
		isDir := e.IsDir()
		if !isDir && (e.Type()&os.ModeSymlink) != 0 {
			if st, err := os.Stat(filepath.Join(abs, name)); err == nil {
				isDir = st.IsDir()
			}
		}
		flag := "F"
		if isDir {
			flag = "D"
		}
		_, _ = w.Write([]byte(name + "\t" + flag + "\n"))
	}
}

func (h *filesHandler) read(w http.ResponseWriter, r *http.Request, abs string) {
	st, err := os.Stat(abs)
	if errors.Is(err, os.ErrNotExist) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if st.IsDir() {
		http.Error(w, "is a directory", http.StatusBadRequest)
		return
	}
	w.Header().Set("Last-Modified", st.ModTime().UTC().Format(http.TimeFormat))
	w.Header().Set("Content-Type",  "application/octet-stream")
	http.ServeFile(w, r, abs)
}

func (h *filesHandler) write(w http.ResponseWriter, r *http.Request, abs string) {
	if err := os.MkdirAll(filepath.Dir(abs), 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	tmp := abs + ".oc-tmp"
	f, err := os.Create(tmp)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if _, err := io.Copy(f, r.Body); err != nil {
		f.Close(); os.Remove(tmp)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.Rename(tmp, abs); err != nil {
		os.Remove(tmp)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Last-Modified", time.Now().UTC().Format(http.TimeFormat))
	w.WriteHeader(http.StatusNoContent)
}

func (h *filesHandler) delete(w http.ResponseWriter, r *http.Request, abs string) {
	if err := os.Remove(abs); err != nil {
		if errors.Is(err, os.ErrNotExist) { http.NotFound(w, r); return }
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *filesHandler) head(w http.ResponseWriter, r *http.Request, abs string) {
	st, err := os.Stat(abs)
	if errors.Is(err, os.ErrNotExist) {
		http.NotFound(w, r); return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Last-Modified", st.ModTime().UTC().Format(http.TimeFormat))
	if !st.IsDir() {
		w.Header().Set("Content-Length", formatInt(st.Size()))
	}
	w.WriteHeader(http.StatusOK)
}

func formatInt(n int64) string {
	if n == 0 { return "0" }
	digits := []byte{}
	neg := n < 0
	if neg { n = -n }
	for n > 0 { digits = append([]byte{byte('0' + n%10)}, digits...); n /= 10 }
	if neg { digits = append([]byte{'-'}, digits...) }
	return string(digits)
}

func (h *filesHandler) rename(w http.ResponseWriter, r *http.Request, oldAbs, newRel string) {
	newAbs, err := h.resolve(newRel)
	if err != nil {
		http.Error(w, "forbidden: "+err.Error(), http.StatusForbidden)
		return
	}
	if _, err := os.Stat(oldAbs); errors.Is(err, os.ErrNotExist) {
		http.NotFound(w, r); return
	}
	if err := os.MkdirAll(filepath.Dir(newAbs), 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.Rename(oldAbs, newAbs); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *filesHandler) mkdir(w http.ResponseWriter, r *http.Request, abs string) {
	if err := os.MkdirAll(abs, 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
