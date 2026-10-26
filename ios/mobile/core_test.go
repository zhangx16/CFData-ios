package core

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMobileAuthentication(t *testing.T) {
	handler := mobileAuthenticate(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }), "127.0.0.1:13335", "secret")
	for _, tc := range []struct {
		name, host, path, cookie string
		status                   int
	}{
		{"unauthenticated", "127.0.0.1:13335", "/", "", 401},
		{"bootstrap", "127.0.0.1:13335", "/?bootstrap=secret", "", 303},
		{"wrong token", "127.0.0.1:13335", "/?bootstrap=wrong", "", 401},
		{"authenticated websocket", "127.0.0.1:13335", "/ws", "secret", 204},
		{"foreign host", "evil.example", "/", "secret", 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://"+tc.host+tc.path, nil)
			if tc.cookie != "" {
				r.AddCookie(&http.Cookie{Name: mobileCookie, Value: tc.cookie})
			}
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, r)
			if w.Code != tc.status {
				t.Fatalf("got %d, want %d", w.Code, tc.status)
			}
			if tc.name == "bootstrap" {
				cookies := w.Result().Cookies()
				if len(cookies) != 1 || !cookies[0].HttpOnly || cookies[0].SameSite != http.SameSiteStrictMode {
					t.Fatal("missing bootstrap cookie protection")
				}
			}
		})
	}
}

func TestMobilePauseCancelsActiveTask(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	s := &appSession{taskCancel: cancel, emit: func(string, interface{}) {}}
	mobileTrackSession(s)
	defer mobileUntrackSession(s)
	defer MobileResume()
	MobilePause()
	if ctx.Err() != context.Canceled {
		t.Fatal("active task was not canceled")
	}
	if mobileAllowRequest(s, "start_task") {
		t.Fatal("background scan allowed")
	}
	MobileResume()
	if !mobileAllowRequest(s, "start_task") {
		t.Fatal("foreground scan blocked")
	}
	if mobileAllowRequest(s, "run_in_background") {
		t.Fatal("persistent background task allowed")
	}
}
