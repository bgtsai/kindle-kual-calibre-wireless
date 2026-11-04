package main

import (
	"log"
	"sync"
	"time"
)

// Auto-disconnect timers (decided with the user, see CLAUDE.md):
// 5 min after connecting with no book; 3 min idle after the last book.
// calibre's eject ends the session by itself (UNCaGED returns from Start).
var (
	noBookTimeout    = 5 * time.Minute
	afterBookTimeout = 3 * time.Minute
)

// idleTimer ends the session through UNCaGED's exit channel when it fires.
// Re-arming replaces the previous countdown; stop() pauses it (while a book is received).
type idleTimer struct {
	mu   sync.Mutex
	t    *time.Timer
	exit chan<- bool
}

func newIdleTimer(exit chan<- bool) *idleTimer { return &idleTimer{exit: exit} }

func (it *idleTimer) arm(d time.Duration, why string) {
	if it == nil {
		return
	}
	it.mu.Lock()
	defer it.mu.Unlock()
	if it.t != nil {
		it.t.Stop()
	}
	if d <= 0 {
		it.t = nil
		return
	}
	it.t = time.AfterFunc(d, func() {
		log.Printf("auto-disconnect: %s for %s", why, d)
		// Start()'s select reads the channel; send in a goroutine so a session that
		// already ended (nobody reading) can't block this timer goroutine forever.
		go func() { it.exit <- true }()
	})
}

func (it *idleTimer) stop() {
	if it == nil {
		return
	}
	it.mu.Lock()
	defer it.mu.Unlock()
	if it.t != nil {
		it.t.Stop()
		it.t = nil
	}
}
