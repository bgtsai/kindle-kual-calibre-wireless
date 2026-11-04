package main

// Kindle home-screen cover thumbnails.
//
// calibre's wireless driver does not write Kindle thumbnails (only its USB
// KINDLE2 driver does), so we replicate calibre/devices/kindle/driver.py:
//   - name:  system/thumbnails/thumbnail_{uuid}_{cdetype}_portrait.jpg
//     uuid = EXTH 113 (ASIN), cdetype = EXTH 501 (e.g. EBOK/PDOC) of the MOBI/AZW3 file
//   - also keep a copy in amazon-cover-bug/ and restore missing ones on every
//     connect: the Kindle firmware sometimes deletes thumbnails of sideloaded
//     books (calibre's sync_cover_thumbnails, mobileread thread 329945).
// KFX is not handled yet (calibre uses read_book_key_kfx); such books get no thumbnail.

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// readExth returns EXTH 113 (uuid/ASIN) and 501 (cdetype) of a MOBI/AZW3 file.
func readExth(path string) (uuid, cdetype string, err error) {
	f, err := os.Open(path)
	if err != nil {
		return "", "", err
	}
	defer f.Close()
	// PalmDB header is 78 bytes; the record list follows, entry 0 = offset of record 0.
	hdr := make([]byte, 86)
	if _, err := io.ReadFull(f, hdr); err != nil {
		return "", "", fmt.Errorf("short PalmDB header: %w", err)
	}
	if string(hdr[60:68]) != "BOOKMOBI" {
		return "", "", errors.New("not a MOBI/AZW3 file")
	}
	rec0 := int64(binary.BigEndian.Uint32(hdr[78:82]))
	// record 0: 16-byte PalmDOC header, then the MOBI header.
	mh := make([]byte, 0x84)
	if _, err := f.ReadAt(mh, rec0); err != nil {
		return "", "", fmt.Errorf("short MOBI header: %w", err)
	}
	if string(mh[16:20]) != "MOBI" {
		return "", "", errors.New("MOBI header magic missing")
	}
	mobiLen := int64(binary.BigEndian.Uint32(mh[20:24]))
	if binary.BigEndian.Uint32(mh[0x80:0x84])&0x40 == 0 {
		return "", "", errors.New("no EXTH block")
	}
	exthOff := rec0 + 16 + mobiLen
	eh := make([]byte, 12)
	if _, err := f.ReadAt(eh, exthOff); err != nil || string(eh[0:4]) != "EXTH" {
		return "", "", errors.New("EXTH magic missing")
	}
	exthLen := binary.BigEndian.Uint32(eh[4:8])
	if exthLen < 12 || exthLen > 1<<20 {
		return "", "", fmt.Errorf("implausible EXTH length %d", exthLen)
	}
	body := make([]byte, exthLen-12)
	if _, err := f.ReadAt(body, exthOff+12); err != nil {
		return "", "", fmt.Errorf("short EXTH: %w", err)
	}
	count := binary.BigEndian.Uint32(eh[8:12])
	r := bytes.NewReader(body)
	for i := uint32(0); i < count; i++ {
		var typ, l uint32
		if binary.Read(r, binary.BigEndian, &typ) != nil || binary.Read(r, binary.BigEndian, &l) != nil || l < 8 {
			break
		}
		data := make([]byte, l-8)
		if _, err := io.ReadFull(r, data); err != nil {
			break
		}
		switch typ {
		case 113:
			uuid = string(data)
		case 501:
			cdetype = string(data)
		}
	}
	if uuid == "" || cdetype == "" {
		return uuid, cdetype, errors.New("EXTH 113/501 missing")
	}
	return uuid, cdetype, nil
}

// thumbName returns the Kindle thumbnail file name for a book, or "" if unknown.
func thumbName(bookPath string) string {
	ext := strings.ToLower(filepath.Ext(bookPath))
	if ext != ".azw3" && ext != ".mobi" && ext != ".azw" && ext != ".prc" {
		return ""
	}
	uuid, cdetype, err := readExth(bookPath)
	if err != nil {
		log.Printf("thumbnail: %s: %v", filepath.Base(bookPath), err)
		return ""
	}
	return fmt.Sprintf("thumbnail_%s_%s_portrait.jpg", uuid, cdetype)
}

// writeThumb stores calibre's cover (base64 JPEG) for a received book.
func (c *client) writeThumb(bookPath, b64 string) {
	if c.thumbDir == "" || b64 == "" {
		return
	}
	name := thumbName(bookPath)
	if name == "" {
		return
	}
	img, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		log.Printf("thumbnail: bad base64 for %s: %v", filepath.Base(bookPath), err)
		return
	}
	for _, dir := range []string{c.thumbDir, c.coverCacheDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("thumbnail: mkdir %s: %v", dir, err)
			continue
		}
		if err := os.WriteFile(filepath.Join(dir, name), img, 0644); err != nil {
			log.Printf("thumbnail: write %s: %v", filepath.Join(dir, name), err)
		}
	}
	log.Printf("thumbnail written: %s", name)
}

// removeThumb deletes a book's thumbnail and its cached copy. Must run before the book file is removed.
func (c *client) removeThumb(bookPath string) {
	if c.thumbDir == "" {
		return
	}
	name := thumbName(bookPath)
	if name == "" {
		return
	}
	for _, dir := range []string{c.thumbDir, c.coverCacheDir} {
		if err := os.Remove(filepath.Join(dir, name)); err != nil && !errors.Is(err, os.ErrNotExist) {
			log.Printf("thumbnail: remove %s: %v", name, err)
		}
	}
}

// restoreThumbs puts back thumbnails the firmware deleted (amazon cover bug).
func (c *client) restoreThumbs() {
	if c.thumbDir == "" {
		return
	}
	ents, err := os.ReadDir(c.coverCacheDir)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Printf("thumbnail: read cache: %v", err)
		}
		return
	}
	n := 0
	for _, e := range ents {
		dst := filepath.Join(c.thumbDir, e.Name())
		if _, err := os.Stat(dst); err == nil {
			continue
		}
		b, err := os.ReadFile(filepath.Join(c.coverCacheDir, e.Name()))
		if err == nil {
			err = os.WriteFile(dst, b, 0644)
		}
		if err != nil {
			log.Printf("thumbnail: restore %s: %v", e.Name(), err)
			continue
		}
		n++
	}
	if n > 0 {
		log.Printf("restored %d thumbnail(s) deleted by the firmware", n)
	}
}
