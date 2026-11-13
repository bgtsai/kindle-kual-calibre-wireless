package main

// Change an entry's "last opened" time (cc.db Entries.p_lastAccess) through the Kindle
// library service itself (com.lab126.ccat, HTTP on 127.0.0.1:9101), which is what the
// "Recent" sort of the library uses. Used by session.sh to keep the "Calibre 連線" book
// first and KUAL last (v0.10.0; header-case fix v0.11.0).
//
// Why not sqlite3 directly: the index EntriesLastAccessIndex is
// (p_lastAccess DESC, p_titles_0_collation COLLATE icu); the stand-alone sqlite3 on the
// Kindle has no "icu" collation, so any UPDATE of p_lastAccess fails with
// "no such collation sequence: icu" (5.13.5; reproduced in the cloud). The service has ICU,
// writes in its own transaction (no second writer on the file) and notifies the UI
// (change.lua: send_change_notification()).
//
// Request format as used by LibrarianSync (cc_update.py) on 5.12+/5.13: POST /change with
// header AuthToken = contents of /tmp/session_token (changes every boot). change.lua turns
// {"update":{"uuid":U,"lastAccess":N}} into UPDATE Entries SET p_lastAccess=N WHERE p_uuid=U
// (min/max changes 1, so an unknown uuid fails and is rolled back).

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

var (
	ccatURL       = "http://127.0.0.1:9101/change"
	ccatTokenFile = "/tmp/session_token"
	// Local service; a hung service must not keep the session cleanup waiting.
	ccatTimeout = 10 * time.Second
)

type ccatResponse struct {
	OK      bool   `json:"ok"`
	Changes int    `json:"changes"`
	Type    string `json:"type"`
	Error   string `json:"error"`
}

// setLastAccess handles "-set-last-access uuid=unixtime[,uuid=unixtime…]".
// One request per entry so one failure doesn't roll back the others.
// Returns the process exit code: 0 all ok, 1 any failure.
func setLastAccess(spec string) int {
	token, err := os.ReadFile(ccatTokenFile)
	if err != nil {
		// Older firmware didn't need a token; try without one.
		log.Printf("set-last-access: no token (%v), sending without AuthToken", err)
	}
	rc := 0
	for _, pair := range strings.Split(spec, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		i := strings.LastIndex(pair, "=")
		if i <= 0 {
			log.Printf("set-last-access: bad item %q (want uuid=unixtime)", pair)
			rc = 1
			continue
		}
		uuid := pair[:i]
		ts, err := strconv.ParseInt(pair[i+1:], 10, 64)
		if err != nil {
			log.Printf("set-last-access: bad time in %q: %v", pair, err)
			rc = 1
			continue
		}
		if err := ccatUpdateLastAccess(strings.TrimSpace(string(token)), uuid, ts); err != nil {
			log.Printf("set-last-access %s=%d failed: %v", uuid, ts, err)
			rc = 1
		} else {
			log.Printf("set-last-access %s=%d ok", uuid, ts)
		}
	}
	return rc
}

func ccatUpdateLastAccess(token, uuid string, ts int64) error {
	body, _ := json.Marshal(map[string]interface{}{
		"commands": []interface{}{
			map[string]interface{}{"update": map[string]interface{}{"uuid": uuid, "lastAccess": ts}},
		},
		"type": "ChangeRequest",
		"id":   1,
	})
	req, err := http.NewRequest("POST", ccatURL, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		// Set the map directly: Header.Set would canonicalize the name to "Authtoken", and the
		// Kindle's service answered that with HTTP 401 "Unauthorized request." (v0.10.0 on
		// 5.13.5). LibrarianSync (Python requests) sends "AuthToken" exactly like this.
		req.Header["AuthToken"] = []string{token}
	}
	// No proxy: the service is on loopback.
	cl := &http.Client{Timeout: ccatTimeout, Transport: &http.Transport{Proxy: nil}}
	resp, err := cl.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	var r ccatResponse
	if err := json.Unmarshal(raw, &r); err != nil {
		return fmt.Errorf("bad response %q: %v", strings.TrimSpace(string(raw)), err)
	}
	if !r.OK {
		return fmt.Errorf("service said not ok: %s", strings.TrimSpace(string(raw)))
	}
	return nil
}
