package main

// Books sent over USB (decided with the user 2026-11-05): calibre's USB driver keeps
// its own list of the books it put on the Kindle in <drive root>/metadata.calibre
// (calibre devices/usbms/driver.py METADATA_CACHE, a JSON list written by JsonCodec,
// same fields as the wireless protocol's book metadata). Without it, calibre's
// "Device" view over Wi-Fi only showed the books this client had received itself.
//
// lpath there is relative to the drive root ("documents/<author>/<book>.azw3");
// ours is relative to bookDir (/mnt/us/documents), so the "documents/" part is cut.
// These books are kept in c.books (so calibre sees them and can delete them) but are
// never written to our own state file: metadata.calibre stays their only record,
// and a book deleted over Wi-Fi is removed from it too, so the next USB connection
// agrees with what is on the device.

import (
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/shermp/UNCaGED/uc"
)

// usbRel turns a USB-driver lpath into one relative to bookDir; ok=false if it is
// outside bookDir (other folders on the drive are not ours to report).
func (c *client) usbRel(lpath string) (string, bool) {
	lp := filepath.ToSlash(lpath)
	prefix := filepath.ToSlash(filepath.Base(c.bookDir)) + "/" // "documents/"
	if len(lp) > len(prefix) && strings.EqualFold(lp[:len(prefix)], prefix) {
		return lp[len(prefix):], true
	}
	return "", false
}

// loadUSBCache adds the USB driver's books whose files still exist and that we don't
// already track. Errors only get logged: the wireless session must work without it.
func (c *client) loadUSBCache() {
	if c.usbCacheFile == "" {
		return
	}
	b, err := os.ReadFile(c.usbCacheFile)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	if err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	var raw []json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		log.Printf("usb metadata %s unreadable, ignored: %v", c.usbCacheFile, err)
		return
	}
	c.usb = map[string]string{}
	added := 0
	for _, r := range raw {
		var md uc.CalibreBookMeta
		if err := json.Unmarshal(r, &md); err != nil {
			log.Printf("usb metadata: skipped one entry: %v", err)
			continue
		}
		rel, ok := c.usbRel(md.Lpath)
		if !ok || c.find(rel) >= 0 {
			continue
		}
		if _, err := os.Stat(filepath.Join(c.bookDir, rel)); err != nil {
			continue // deleted on the Kindle since the last USB connection
		}
		c.usb[rel] = md.Lpath
		md.Lpath = rel
		md.Thumbnail = nil // calibre doesn't need it in the book list
		c.books = append(c.books, md)
		added++
	}
	log.Printf("usb metadata: %d book(s) sent over USB added to the list", added)
}

// ownBooks is c.books without the USB-driver books (what goes into our state file).
func (c *client) ownBooks() []uc.CalibreBookMeta {
	if len(c.usb) == 0 {
		return c.books
	}
	out := make([]uc.CalibreBookMeta, 0, len(c.books))
	for _, md := range c.books {
		if _, isUSB := c.usb[md.Lpath]; !isUSB {
			out = append(out, md)
		}
	}
	return out
}

// forgetUSBBook removes a deleted book's entry from metadata.calibre. Other entries
// are written back byte for byte (json.RawMessage), so fields this client doesn't
// know about survive. Temp file + rename, like our own state file.
func (c *client) forgetUSBBook(rel string) {
	orig, ok := c.usb[rel]
	if !ok {
		return
	}
	delete(c.usb, rel)
	b, err := os.ReadFile(c.usbCacheFile)
	if err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	var raw []json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	kept := raw[:0]
	removed := 0
	for _, r := range raw {
		var e struct {
			Lpath string `json:"lpath"`
		}
		if json.Unmarshal(r, &e) == nil && e.Lpath == orig {
			removed++
			continue
		}
		kept = append(kept, r)
	}
	if removed == 0 {
		return
	}
	out, err := json.Marshal(kept)
	if err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	tmp := c.usbCacheFile + ".tmp"
	if err := os.WriteFile(tmp, out, 0644); err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	if err := os.Rename(tmp, c.usbCacheFile); err != nil {
		log.Printf("usb metadata: %v", err)
		return
	}
	log.Printf("usb metadata: removed %s", orig)
}
