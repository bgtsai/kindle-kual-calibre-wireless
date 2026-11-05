// calibre-wireless — Kindle client for calibre's "wireless device connection"
// (Smart Device App protocol), built on the UNCaGED library.
//
// v0.7.0: also lists books sent over USB (metadata.calibre), deleting them updates that file.
// v0.6.0: keep searching for calibre up to 5 min (-search-timeout).
// v0.5.0: one folder per book (documents/<title>/<title> - <authors>.<ext>), .sdr cleanup on delete.
// v0.4.0: discover calibre (subnet-broadcast fallback), receive / list / delete books,
// Kindle home-screen cover thumbnails (+ amazon-cover-bug restore), device name shown
// in calibre, Chinese file names (traditional / simplified / original,
// calibre-wireless.conf), auto-disconnect timers, progress lines for the KUAL wrapper.
// Airplane mode, sleep prevention and library rescan are done by bin/session.sh.
//
// Log lines bin/session.sh matches (keep in sync): "connected to calibre",
// "book <n>/<N> received", "auto-disconnect".
//
// Copyright (C) 2026 bgtsai. Licensed under GPL-3.0-or-later (UNCaGED is GPL-3.0).
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/bgtsai/kindle-kual-calibre-wireless/zhconv"
	"github.com/shermp/UNCaGED/uc"
)

const version = "0.7.0"

// client implements uc.Client. Metadata for every book calibre sent is kept in
// one JSON file (stateFile) so calibre's "On device" column survives reconnects.
type client struct {
	bookDir       string
	stateFile     string
	devName       string
	thumbDir      string // Kindle system/thumbnails; "" disables thumbnails
	coverCacheDir string // copies used to undo the amazon cover bug
	books         []uc.CalibreBookMeta
	files         map[string]string // calibre lpath → file name in bookDir (see naming.go)
	cfg           Config
	conv          *zhconv.Converter // nil = keep calibre's script
	devInfo       uc.DeviceInfo
	exitChan      chan<- bool
	idle          *idleTimer
	bookNo        int // 1-based number of the book being received (calibre's thisBook+1)
	bookTotal     int
	sessionUp     bool              // "connected to calibre" logged, no-book timer armed
	usbCacheFile  string            // calibre USB driver's metadata.calibre (usbcache.go)
	usb           map[string]string // lpath (ours) → lpath in metadata.calibre, for books sent over USB
}

type state struct {
	Books   []uc.CalibreBookMeta `json:"books"`
	Files   map[string]string    `json:"files,omitempty"`
	DevInfo uc.DeviceInfo        `json:"device_info"`
}

func (c *client) load() error {
	b, err := os.ReadFile(c.stateFile)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var s state
	if err := json.Unmarshal(b, &s); err != nil {
		return fmt.Errorf("state file %s is corrupt: %w", c.stateFile, err)
	}
	// Drop entries whose file was deleted on the Kindle (e.g. from the Kindle UI),
	// otherwise calibre would keep showing them as "on device".
	c.files = map[string]string{}
	for _, md := range s.Books {
		f := md.Lpath
		if v, ok := s.Files[md.Lpath]; ok {
			f = v
		}
		if _, err := os.Stat(filepath.Join(c.bookDir, f)); err == nil {
			c.books = append(c.books, md)
			if f != md.Lpath {
				c.files[md.Lpath] = f
			}
		} else {
			log.Printf("state: %s no longer on device, dropped", f)
		}
	}
	c.devInfo = s.DevInfo
	return nil
}

// save writes to a temp file then renames, so a crash mid-write can't corrupt the list.
func (c *client) save() error {
	b, err := json.Marshal(state{Books: c.ownBooks(), Files: c.files, DevInfo: c.devInfo})
	if err != nil {
		return err
	}
	tmp := c.stateFile + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, c.stateFile)
}

func (c *client) find(lpath string) int {
	for i, md := range c.books {
		if md.Lpath == lpath {
			return i
		}
	}
	return -1
}

func (c *client) SelectCalibreInstance(ins []uc.CalInstance) uc.CalInstance {
	log.Printf("found %d calibre instance(s), using %s at %s", len(ins), ins[0].Name, ins[0].Host)
	return ins[0]
}

func (c *client) GetClientOptions() (uc.ClientOptions, error) {
	var o uc.ClientOptions
	o.ClientName = "calibre-wireless"
	o.DeviceName = c.devName
	o.DeviceModel = "Kindle"
	// Formats the Kindle reader opens natively; calibre converts others to the first one it can.
	o.SupportedExt = []string{"azw3", "mobi", "azw", "pdf", "txt", "kfx"}
	// calibre's KINDLE2 driver: "x500 on the Oasis 2017. checked that it works on the PW3".
	// Only the height is sent to calibre (coverHeight); width follows the aspect ratio.
	o.CoverDims.Width = 330
	o.CoverDims.Height = 500
	return o, nil
}

func (c *client) GetDeviceBookList() ([]uc.BookCountDetails, error) {
	if len(c.books) == 0 {
		return nil, nil
	}
	out := make([]uc.BookCountDetails, len(c.books))
	for i, md := range c.books {
		lm := time.Now()
		if t := md.LastModified.GetTime(); t != nil {
			lm = *t
		}
		out[i] = uc.BookCountDetails{UUID: md.UUID, Lpath: md.Lpath,
			Extension: filepath.Ext(md.Lpath), LastModified: lm}
	}
	return out, nil
}

type iter struct {
	list []uc.CalibreBookMeta
	pos  int
}

func (it *iter) Next() bool { it.pos++; return it.pos < len(it.list) }
func (it *iter) Count() int { return len(it.list) }
func (it *iter) Get() (uc.CalibreBookMeta, error) {
	if it.pos < 0 || it.pos >= len(it.list) {
		return uc.CalibreBookMeta{}, errors.New("metadata iterator out of range")
	}
	return it.list[it.pos], nil
}

func (c *client) GetMetadataIter(ids []uc.BookID) uc.MetadataIter {
	if ids == nil {
		return &iter{list: c.books, pos: -1}
	}
	var sel []uc.CalibreBookMeta
	for _, id := range ids {
		if i := c.find(id.Lpath); i >= 0 {
			sel = append(sel, c.books[i])
		}
	}
	return &iter{list: sel, pos: -1}
}

func (c *client) GetDeviceInfo() (uc.DeviceInfo, error) { return c.devInfo, nil }

func (c *client) SetDeviceInfo(d uc.DeviceInfo) error {
	c.devInfo.DevInfo = d.DevInfo
	return c.save()
}

func (c *client) SetLibraryInfo(uc.CalibreLibraryInfo) error { return nil }

func (c *client) UpdateMetadata(list []uc.CalibreBookMeta) error {
	for _, md := range list {
		if i := c.find(md.Lpath); i >= 0 {
			c.books[i] = md
		}
	}
	return c.save()
}

func (c *client) GetPassword(uc.CalibreInitInfo) (string, error) { return "", nil }

func (c *client) GetFreeSpace() uint64 {
	var s syscall.Statfs_t
	if err := syscall.Statfs(c.bookDir, &s); err != nil {
		log.Printf("statfs %s failed: %v", c.bookDir, err)
		return 0
	}
	return uint64(s.Bavail) * uint64(s.Bsize)
}

func (c *client) CheckLpath(lpath string) string { return lpath }

func (c *client) SaveBook(md uc.CalibreBookMeta, r io.Reader, n int, last bool) error {
	file := c.pickFile(md)
	dst := filepath.Join(c.bookDir, file)
	if !strings.HasPrefix(filepath.Clean(dst), filepath.Clean(c.bookDir)+string(os.PathSeparator)) {
		return fmt.Errorf("refusing path outside book dir: %q", file)
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	tmp := dst + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	w, err := io.CopyN(f, r, int64(n))
	f.Close()
	if err != nil {
		os.Remove(tmp)
		return fmt.Errorf("receiving %s: got %d of %d bytes: %w", md.Lpath, w, n, err)
	}
	if err := os.Rename(tmp, dst); err != nil {
		return err
	}
	if md.Thumbnail.Exists() {
		c.writeThumb(dst, md.Thumbnail.ImgBase64())
	}
	md.Thumbnail = nil // don't bloat the state file; the image lives in system/thumbnails
	if i := c.find(md.Lpath); i >= 0 {
		c.books[i] = md
	} else {
		c.books = append(c.books, md)
	}
	if file != md.Lpath {
		c.files[md.Lpath] = file
	}
	log.Printf("saved %s as %s (%d bytes) last=%v", md.Lpath, file, n, last)
	log.Printf("book %d/%d received", c.bookNo, c.bookTotal)
	c.idle.arm(afterBookTimeout, "idle after last book")
	return c.save()
}

func (c *client) GetBook(id uc.BookID, pos int64) (io.ReadCloser, int64, error) {
	f, err := os.Open(filepath.Join(c.bookDir, c.fileFor(id.Lpath)))
	if err != nil {
		return nil, 0, err
	}
	st, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, 0, err
	}
	if pos > 0 {
		if _, err := f.Seek(pos, io.SeekStart); err != nil {
			f.Close()
			return nil, 0, err
		}
	}
	return f, st.Size() - pos, nil
}

func (c *client) DeleteBook(id uc.BookID) error {
	i := c.find(id.Lpath)
	path := filepath.Join(c.bookDir, c.fileFor(id.Lpath))
	c.removeThumb(path) // needs the book file to read its EXTH
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	c.removeSidecars(path)
	c.forgetUSBBook(id.Lpath)
	// Deleting books is activity too: restart the idle countdown instead of letting the
	// "no book received" timer cut the user off while they are cleaning up the device.
	c.idle.arm(afterBookTimeout, "idle after last book/delete")
	if i >= 0 {
		c.books = append(c.books[:i], c.books[i+1:]...)
	}
	delete(c.files, id.Lpath)
	log.Printf("deleted %s (%s)", id.Lpath, filepath.Base(path))
	return c.save()
}

// removeSidecars deletes the Kindle's reading-data folders for a deleted book
// (<name>.sdr and <name>_<id>.sdr next to it; the Kindle made both for wireless books,
// seen 2026-11-05) and then the per-book folder if nothing else is left in it.
// Only exact-name matches: "X - A.sdr" must not take "X - A (2).sdr" with it.
func (c *client) removeSidecars(bookPath string) {
	dir := filepath.Dir(bookPath)
	stem := strings.TrimSuffix(filepath.Base(bookPath), filepath.Ext(bookPath))
	ents, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range ents {
		n := e.Name()
		if !e.IsDir() || !strings.HasSuffix(n, ".sdr") {
			continue
		}
		core := strings.TrimSuffix(n, ".sdr")
		if core == stem || strings.HasPrefix(core, stem+"_") {
			if err := os.RemoveAll(filepath.Join(dir, n)); err != nil {
				log.Printf("remove %s: %v", n, err)
			}
		}
	}
	if filepath.Clean(dir) != filepath.Clean(c.bookDir) {
		if err := os.Remove(dir); err == nil { // fails (and is kept) unless empty
			log.Printf("removed empty folder %s", filepath.Base(dir))
		}
	}
}

// searchTimeout: how long to keep looking for calibre (decided with the user 2026-11-05:
// people tap "connect" on the Kindle first and only then open calibre). One UNCaGED
// discovery round takes only a few seconds, so it is repeated every searchRetryInterval.
// time.Since uses Go's monotonic clock (CLOCK_MONOTONIC), which does not advance while
// the Kindle is suspended, so sleeping doesn't use up the search time.
var (
	searchTimeout       = 5 * time.Minute
	searchRetryInterval = 2 * time.Second
)

// findCalibre retries discovery until calibre answers or searchTimeout passes.
// "Not found" and broadcast send errors (no route yet right after boot, KB 32 §8) are
// retried; anything else (e.g. reading our own state) fails at once.
// starter is what main needs from UNCaGED's (unexported) connection type.
type starter interface{ Start() error }

func findCalibre(c *client, debug bool, timeout time.Duration) (starter, error) {
	start := time.Now()
	logged := false
	for {
		conn, err := uc.New(c, debug)
		if err == nil {
			return conn, nil
		}
		retry := errors.Is(err, uc.CalibreNotFound) || strings.Contains(err.Error(), "error getting calibre instances")
		if !retry || time.Since(start) >= timeout {
			return nil, err
		}
		if !logged {
			log.Printf("searching for calibre (up to %s): %v", timeout, err)
			logged = true
		}
		time.Sleep(searchRetryInterval)
	}
}

func (c *client) UpdateStatus(s uc.Status, p int) {
	log.Printf("status %d progress %d", s, p)
	// UNCaGED only reports Connected when calibre asks GET_DEVICE_INFORMATION, which
	// calibre 7.6 doesn't do (tested); Idle/Waiting arrive once the session is up.
	// Only the first one arms the no-book timer: Idle repeats on every NOOP.
	if !c.sessionUp && (s == uc.Connected || s == uc.Idle || s == uc.Waiting) {
		c.sessionUp = true
		log.Printf("connected to calibre")
		if c.bookNo == 0 { // a book already started: its own idle timer is in charge
			c.idle.arm(noBookTimeout, "no book received")
		}
	}
}

// BookStart implements the patched uc.BookProgresser (third_party/UNCaGED): called
// before each SaveBook with calibre's thisBook (0-based) and totalBooks.
// The idle timer is stopped while a book is being received (a big book can take minutes).
func (c *client) BookStart(thisBook, totalBooks int) {
	c.bookNo, c.bookTotal = thisBook+1, totalBooks
	c.idle.stop()
}

func (c *client) LogPrintf(l uc.LogLevel, f string, a ...interface{}) {
	log.Printf("[uc %d] "+f, append([]interface{}{l}, a...)...)
}

func (c *client) SetExitChannel(ch chan<- bool) {
	c.exitChan = ch
	c.idle = newIdleTimer(ch)
}

func main() {
	// Own FlagSet: the OpenCC package used up to v0.8.0 registered a global "-dir" flag in
	// its init() ("flag redefined: dir"). Kept so a future dependency can't do that again.
	flag := flag.NewFlagSet(os.Args[0], flag.ExitOnError)
	dir := flag.String("dir", "/mnt/us/documents", "where received books are stored")
	stateFile := flag.String("state", "", "metadata state file (default: <dir>/.calibre-wireless.json)")
	name := flag.String("name", "Kindle", "device name shown in calibre")
	thumbDir := flag.String("thumbs", "/mnt/us/system/thumbnails", "Kindle thumbnail dir (empty = no thumbnails)")
	coverCache := flag.String("cover-cache", "/mnt/us/amazon-cover-bug", "thumbnail backup dir (same as calibre's USB driver)")
	confFile := flag.String("conf", "", "settings file (default: calibre-wireless.conf next to the program's bin/ dir)")
	debug := flag.Bool("debug", false, "verbose protocol log")
	usbCache := flag.String("usb-metadata", "", "calibre USB driver's book list (default: metadata.calibre one level above -dir; \"none\" = ignore)")
	flag.DurationVar(&searchTimeout, "search-timeout", searchTimeout, "keep looking for calibre this long (users often tap connect first, then start calibre)")
	flag.DurationVar(&noBookTimeout, "no-book-timeout", noBookTimeout, "disconnect if no book arrives this long after connecting (0 = never)")
	flag.DurationVar(&afterBookTimeout, "idle-timeout", afterBookTimeout, "disconnect this long after the last book or delete (0 = never)")
	flag.Parse(os.Args[1:])
	log.SetFlags(log.Ldate | log.Ltime)
	log.Printf("calibre-wireless v%s starting, dir=%s", version, *dir)

	c := &client{bookDir: *dir, stateFile: *stateFile, devName: *name,
		thumbDir: *thumbDir, coverCacheDir: *coverCache, files: map[string]string{}}
	if *confFile == "" {
		if exe, err := os.Executable(); err == nil {
			*confFile = filepath.Join(filepath.Dir(filepath.Dir(exe)), "calibre-wireless.conf")
		}
	}
	c.cfg = loadConfig(*confFile)
	c.conv = newConverter(c.cfg.FilenameChinese)
	log.Printf("config %s: filename_chinese=%s", *confFile, c.cfg.FilenameChinese)
	if c.stateFile == "" {
		c.stateFile = filepath.Join(*dir, ".calibre-wireless.json")
	}
	if err := c.load(); err != nil {
		log.Fatalf("load state: %v", err)
	}
	switch *usbCache {
	case "":
		c.usbCacheFile = filepath.Join(filepath.Dir(filepath.Clean(*dir)), "metadata.calibre")
	case "none":
	default:
		c.usbCacheFile = *usbCache
	}
	c.loadUSBCache()
	// calibre shows "Wireless device: <deviceName>"; UNCaGED takes the name from DevInfo,
	// which is empty until calibre has set it once (v0.1.0 showed only "Wireless device").
	if c.devInfo.DevInfo.DeviceName == "" {
		c.devInfo.DevInfo.DeviceName = c.devName
	}
	if c.devInfo.DeviceVersion == "" {
		c.devInfo.DeviceVersion = "Kindle"
	}
	c.restoreThumbs()
	conn, err := findCalibre(c, *debug, searchTimeout)
	if err != nil {
		if errors.Is(err, uc.CalibreNotFound) {
			log.Printf("calibre not found on the network")
			os.Exit(2)
		}
		log.Fatalf("connect: %v", err)
	}
	if err := conn.Start(); err != nil {
		log.Fatalf("session ended with error: %v", err)
	}
	log.Printf("disconnected")
}
