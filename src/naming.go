package main

// Chinese file names on the Kindle.
//
// calibre always builds the device path (lpath) with ascii_filename(), so a
// Chinese title arrives as pinyin ("Ce Shi Shu Yi - Zuo Zhe Jia (12).azw3");
// both the USB and the wireless driver do this and there is no calibre option
// to turn it off (launchpad bug 812321, Won't Fix). We keep calibre's lpath as
// the key calibre knows the book by, but store the file under
// "<title> - <authors>.<ext>" in the script chosen by filename_chinese, and
// remember lpath → file name in the state file.

import (
	"bufio"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/bgtsai/kindle-kual-calibre-wireless/zhconv"
	"github.com/shermp/UNCaGED/uc"
)

// Config is read from calibre-wireless.conf (key=value, # comments).
type Config struct {
	FilenameChinese string // traditional | simplified | original
}

func defaultConfig() Config { return Config{FilenameChinese: "traditional"} }

func loadConfig(path string) Config {
	cfg := defaultConfig()
	f, err := os.Open(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Printf("config: %v (using defaults)", err)
		}
		return cfg
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		switch k {
		case "filename_chinese":
			switch v {
			case "traditional", "simplified", "original":
				cfg.FilenameChinese = v
			default:
				log.Printf("config: filename_chinese=%q unknown, using %q", v, cfg.FilenameChinese)
			}
		default:
			log.Printf("config: unknown key %q ignored", k)
		}
	}
	return cfg
}

// newConverter returns the OpenCC converter for the setting, or nil for "original".
// s2tw / tw2s convert characters with Taiwan standard forms but do NOT swap
// vocabulary (s2twp would turn 鼠标 into 滑鼠) — book titles should keep their words.
func newConverter(mode string) *zhconv.Converter {
	conv := map[string]string{"traditional": "s2tw", "simplified": "tw2s"}[mode]
	if conv == "" {
		return nil
	}
	cc, err := zhconv.New(conv)
	if err != nil {
		log.Printf("opencc %s: %v (file names keep calibre's script)", conv, err)
		return nil
	}
	return cc
}

// FAT32 (/mnt/us) and Windows forbid these; the user also opens the folder over USB on Windows.
var badChars = strings.NewReplacer(`\`, "_", "/", "_", ":", "_", "*", "_", "?", "_",
	`"`, "_", "<", "_", ">", "_", "|", "_")

// Windows reserved device names (also with an extension).
var reserved = map[string]bool{"CON": true, "PRN": true, "AUX": true, "NUL": true}

func init() {
	for i := 1; i <= 9; i++ {
		reserved[fmt.Sprintf("COM%d", i)] = true
		reserved[fmt.Sprintf("LPT%d", i)] = true
	}
}

// maxNameRunes keeps names well under FAT32's 255 UTF-16 units including extension and " (99)".
const maxNameRunes = 120

func sanitizeName(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < 32 || r == 0x7f || (r >= 0x200b && r <= 0x200f) || (r >= 0x202a && r <= 0x202e) || r == 0xfeff {
			return -1 // control and invisible direction/zero-width characters
		}
		return r
	}, s)
	s = badChars.Replace(s)
	s = strings.Join(strings.Fields(s), " ")
	if utf8.RuneCountInString(s) > maxNameRunes {
		s = string([]rune(s)[:maxNameRunes])
	}
	s = strings.TrimRight(s, " .") // Windows drops trailing dots/spaces
	if s == "" || reserved[strings.ToUpper(s)] {
		s = "_" + s
	}
	return s
}

// chineseName builds "<title> - <authors>" (USB driver's default template, without calibre's "(id)").
func (c *client) chineseName(md uc.CalibreBookMeta) string {
	name := strings.TrimSpace(md.Title)
	if a := strings.Join(md.Authors, " & "); a != "" {
		name += " - " + a
	}
	if c.conv != nil {
		if out, err := c.conv.Convert(name); err == nil {
			name = out
		} else {
			log.Printf("opencc convert %q: %v", name, err)
		}
	}
	return sanitizeName(name)
}

// folderName is the per-book folder (decided 2026-11-05): the book title, converted and
// sanitized like the file name, so documents/ holds one entry per book instead of the
// book plus the .sdr folders the Kindle creates next to it.
func (c *client) folderName(md uc.CalibreBookMeta) string {
	t := strings.TrimSpace(md.Title)
	if t == "" {
		return ""
	}
	if c.conv != nil {
		if out, err := c.conv.Convert(t); err == nil {
			t = out
		}
	}
	t = sanitizeName(t)
	if t == "_" {
		return ""
	}
	return t
}

// fileFor returns the on-device file name (relative to bookDir) for a calibre lpath.
// Books from v0.2.0 and earlier have no entry and are stored under the lpath itself.
func (c *client) fileFor(lpath string) string {
	if f, ok := c.files[lpath]; ok {
		return f
	}
	return lpath
}

// pickFile chooses a free file name for a newly received book. Re-sending the same
// lpath (calibre "update book") reuses the existing file.
func (c *client) pickFile(md uc.CalibreBookMeta) string {
	if f, ok := c.files[md.Lpath]; ok {
		return f
	}
	if c.cfg.FilenameChinese == "original" && md.Title == "" {
		return md.Lpath
	}
	ext := filepath.Ext(md.Lpath)
	base := c.chineseName(md)
	if base == "" || base == "_" {
		return md.Lpath
	}
	// documents/<title>/<title> - <authors>.<ext>; books with no usable title stay at the top.
	if dir := c.folderName(md); dir != "" {
		base = dir + "/" + base
	}
	used := map[string]bool{}
	for _, f := range c.files {
		used[strings.ToLower(f)] = true // FAT32 is case-insensitive
	}
	for i := 1; ; i++ {
		name := base + ext
		if i > 1 {
			name = fmt.Sprintf("%s (%d)%s", base, i, ext)
		}
		if used[strings.ToLower(name)] {
			continue
		}
		if _, err := os.Stat(filepath.Join(c.bookDir, name)); err == nil {
			continue // a book not sent by calibre already has this name
		}
		return name
	}
}
