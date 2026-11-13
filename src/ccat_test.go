package main

import (
	"bufio"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Fake library service: checks what change.lua and the 5.12+ AuthToken check need,
// answers like change.lua's rv ({"ok":true,"changes":1,"type":"ChangeResponse"}).
func fakeCcat(t *testing.T, token string, reply string, status int, got *[]map[string]interface{}) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Path != "/change" {
			t.Errorf("want POST /change, got %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("AuthToken") != token {
			t.Errorf("AuthToken = %q, want %q", r.Header.Get("AuthToken"), token)
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Content-Type = %q", r.Header.Get("Content-Type"))
		}
		raw, _ := io.ReadAll(r.Body)
		var body map[string]interface{}
		if err := json.Unmarshal(raw, &body); err != nil {
			t.Errorf("body not JSON: %s", raw)
		}
		*got = append(*got, body)
		w.WriteHeader(status)
		io.WriteString(w, reply)
	}))
}

func setupCcat(t *testing.T, srv *httptest.Server, token string) {
	dir := t.TempDir()
	tf := filepath.Join(dir, "session_token")
	os.WriteFile(tf, []byte(token+"\n"), 0600) // trailing newline must be trimmed
	oldURL, oldTok := ccatURL, ccatTokenFile
	ccatURL, ccatTokenFile = srv.URL+"/change", tf
	t.Cleanup(func() { ccatURL, ccatTokenFile = oldURL, oldTok })
}

func TestSetLastAccessOK(t *testing.T) {
	var got []map[string]interface{}
	srv := fakeCcat(t, "tok123", `{"ok":true,"changes":1,"type":"ChangeResponse"}`, 200, &got)
	defer srv.Close()
	setupCcat(t, srv, "tok123")
	if rc := setLastAccess("aaa-1=1825000000,bbb-2=946684800"); rc != 0 {
		t.Fatalf("rc = %d, want 0", rc)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 requests (one per entry), got %d", len(got))
	}
	want := []struct {
		uuid string
		ts   float64
	}{{"aaa-1", 1825000000}, {"bbb-2", 946684800}}
	for i, b := range got {
		if b["type"] != "ChangeRequest" {
			t.Errorf("type = %v", b["type"])
		}
		cmds, _ := b["commands"].([]interface{})
		if len(cmds) != 1 {
			t.Fatalf("commands = %v", b["commands"])
		}
		u := cmds[0].(map[string]interface{})["update"].(map[string]interface{})
		if u["uuid"] != want[i].uuid || u["lastAccess"] != want[i].ts || len(u) != 2 {
			t.Errorf("update %d = %v, want uuid=%s lastAccess=%v only", i, u, want[i].uuid, want[i].ts)
		}
	}
}

func TestSetLastAccessFailures(t *testing.T) {
	cases := []struct {
		name, reply string
		status      int
	}{
		{"not ok", `{"ok":false,"error":"min_changes"}`, 200},
		{"http error", `unauthorized`, 401},
		{"not json", `<html>`, 200},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var got []map[string]interface{}
			srv := fakeCcat(t, "tok", c.reply, c.status, &got)
			defer srv.Close()
			setupCcat(t, srv, "tok")
			if rc := setLastAccess("u=1"); rc != 1 {
				t.Errorf("rc = %d, want 1", rc)
			}
		})
	}
}

func TestSetLastAccessBadSpec(t *testing.T) {
	var got []map[string]interface{}
	srv := fakeCcat(t, "tok", `{"ok":true}`, 200, &got)
	defer srv.Close()
	setupCcat(t, srv, "tok")
	// bad items fail, good ones are still sent
	if rc := setLastAccess("noequals,u=notanumber,ok-1=5"); rc != 1 {
		t.Errorf("rc = %d, want 1", rc)
	}
	if len(got) != 1 {
		t.Errorf("want only the valid item sent, got %d requests", len(got))
	}
}

// The header name must go out as "AuthToken" exactly: the Kindle's service answered
// Go's canonical "Authtoken" with 401 (v0.10.0, 5.13.5). net/http servers canonicalize
// incoming names, so read the raw request bytes.
func TestSetLastAccessHeaderCase(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	raw := make(chan string, 1)
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		br := bufio.NewReader(c)
		var head strings.Builder
		for {
			line, err := br.ReadString('\n')
			head.WriteString(line)
			if err != nil || line == "\r\n" {
				break
			}
		}
		raw <- head.String()
		io.WriteString(c, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 13\r\nConnection: close\r\n\r\n{\"ok\":true}\r\n")
	}()
	dir := t.TempDir()
	tf := filepath.Join(dir, "session_token")
	os.WriteFile(tf, []byte("tok"), 0600)
	oldURL, oldTok := ccatURL, ccatTokenFile
	ccatURL, ccatTokenFile = "http://"+ln.Addr().String()+"/change", tf
	defer func() { ccatURL, ccatTokenFile = oldURL, oldTok }()
	setLastAccess("u=1")
	select {
	case h := <-raw:
		if !strings.Contains(h, "\r\nAuthToken: tok\r\n") {
			t.Errorf("request head lacks exact \"AuthToken: tok\":\n%s", h)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no request received")
	}
}
