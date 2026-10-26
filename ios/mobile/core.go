// This file is copied into the generated internal/core package.
package core

import (
	"crypto/subtle"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const mobileCookie = "cfdata_ios_session"

var mobileState = struct {
	sync.Mutex
	address   string
	directory string
	paused    bool
	sessions  map[*appSession]bool
}{sessions: make(map[*appSession]bool)}

func mobileConfigPath() string {
	return filepath.Join(mobileState.directory, "cfdata-config.json")
}

// MobileStart is called once, off the main UI thread, inside the iOS process.
func MobileStart(directory string) (string, error) {
	mobileState.Lock()
	defer mobileState.Unlock()
	if mobileState.address != "" {
		return mobileState.address, nil
	}
	if !filepath.IsAbs(directory) {
		return "", errors.New("data directory must be absolute")
	}
	if err := os.MkdirAll(directory, 0700); err != nil {
		return "", err
	}
	// Upstream caches and CSV files use relative paths. This dedicated app has
	// one backend; use Application Support rather than the read-only bundle.
	if err := os.Chdir(directory); err != nil {
		return "", err
	}
	mobileState.directory = directory
	token, err := newSessionToken()
	if err != nil {
		return "", err
	}
	// A stable origin preserves WebKit localStorage between launches.
	listener, err := net.Listen("tcp4", "127.0.0.1:13335")
	if err != nil {
		return "", fmt.Errorf("start local backend: %w", err)
	}
	ready := false
	defer func() {
		if !ready {
			_ = listener.Close()
		}
	}()
	speedTestURL = autoSpeedURLValue
	speedTestWorkers = 1
	customDNSServer = defaultDNSServers
	skipGeoCheck = true
	configureHTTPClients()
	if _, _, err := loadOrCreateCLIConfig(mobileConfigPath()); err != nil && !errors.Is(err, errCLIConfigCreated) {
		return "", err
	}
	applyManagementProxyFromConfigFile(mobileConfigPath())
	initLocations()
	origin := "http://" + listener.Addr().String()
	upgrader.CheckOrigin = func(r *http.Request) bool { return r.Header.Get("Origin") == origin }
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", handleWebSocket)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		name, kind := "index.html", "text/html; charset=utf-8"
		if r.URL.Path == "/favicon.png" {
			name, kind = "favicon.png", "image/png"
		} else if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		data, err := staticFiles.ReadFile(name)
		if err != nil {
			http.Error(w, "Unable to load interface", 500)
			return
		}
		w.Header().Set("Content-Type", kind)
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write(data)
	})
	server := &http.Server{
		Handler:           mobileAuthenticate(mux, listener.Addr().String(), token),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			recordProgramDebugError("ios_server", err.Error())
		}
	}()
	mobileState.address = origin + "/?bootstrap=" + token
	ready = true
	return mobileState.address, nil
}

func mobileAuthenticate(next http.Handler, host, token string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != host {
			http.Error(w, "Invalid host", http.StatusForbidden)
			return
		}
		if r.URL.Path == "/" && r.Method == http.MethodGet && subtle.ConstantTimeCompare([]byte(r.URL.Query().Get("bootstrap")), []byte(token)) == 1 {
			http.SetCookie(w, &http.Cookie{Name: mobileCookie, Value: token, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
			http.Redirect(w, r, "/", http.StatusSeeOther)
			return
		}
		cookie, err := r.Cookie(mobileCookie)
		if err != nil || subtle.ConstantTimeCompare([]byte(cookie.Value), []byte(token)) != 1 {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func mobileTrackSession(session *appSession) {
	mobileState.Lock()
	mobileState.sessions[session] = true
	mobileState.Unlock()
}

func mobileUntrackSession(session *appSession) {
	mobileState.Lock()
	delete(mobileState.sessions, session)
	mobileState.Unlock()
}

func mobileAllowRequest(session *appSession, kind string) bool {
	mobileState.Lock()
	paused := mobileState.paused
	mobileState.Unlock()
	if kind == "run_in_background" || (paused && (strings.HasPrefix(kind, "start_") || kind == "compact_ipv4")) {
		session.sendWSMessage("error", "iOS 版本仅支持前台运行，请返回应用后重新开始任务")
		return false
	}
	return true
}

// MobilePause cancels tasks without touching WebSocket ownership or results.
func MobilePause() {
	mobileState.Lock()
	mobileState.paused = true
	sessions := make([]*appSession, 0, len(mobileState.sessions))
	for session := range mobileState.sessions {
		sessions = append(sessions, session)
	}
	mobileState.Unlock()
	for _, session := range sessions {
		session.cancelTaskSilently()
	}
}

func MobileResume() {
	mobileState.Lock()
	mobileState.paused = false
	mobileState.Unlock()
}
