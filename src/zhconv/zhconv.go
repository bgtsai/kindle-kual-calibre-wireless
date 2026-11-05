// Package zhconv converts Simplified <-> Traditional (Taiwan standard) Chinese with the
// OpenCC dictionaries in dict/ (Apache-2.0, see licenses/OpenCC-Apache-2.0.txt and THIRD_PARTY_NOTICES.md at the repo root).
//
// Why our own converter instead of github.com/longbridgeapp/opencc (used up to v0.8.0):
// that package depends on github.com/liuzl/cedar-go, whose license is GPL-2.0 without an
// "or later" grant — possibly incompatible with this project's GPL-3.0. We only need the
// two OpenCC chains s2tw / tw2s, which are plain dictionary lookups, so this file
// reimplements them (decided 2026-11-05).
//
// Algorithm: the dictionary chains of OpenCC's config/s2tw.json and tw2s.json, applied the
// way longbridgeapp/opencc v0.3.13 does (see apply), taking the first candidate of each
// entry. Verified identical to that package on ~13,000 test lines (2026-11-05).
package zhconv

import (
	"bufio"
	"embed"
	"fmt"
	"strings"
)

//go:embed dict/*.txt
var dictFS embed.FS

type dict struct {
	m      map[string]string
	maxLen int // longest key, in runes
}

type stage []dict

// Converter is safe for concurrent use after New returns.
type Converter struct{ stages []stage }

// Chains mirror OpenCC's s2tw.json / tw2s.json.
var chains = map[string][][]string{
	"s2tw": {{"STPhrases", "STCharacters"}, {"TWVariants"}},
	"tw2s": {{"TWVariantsRevPhrases", "TWVariantsRev"}, {"TSPhrases", "TSCharacters"}},
}

// New returns the converter for "s2tw" or "tw2s".
func New(name string) (*Converter, error) {
	chain, ok := chains[name]
	if !ok {
		return nil, fmt.Errorf("unknown conversion %q", name)
	}
	c := &Converter{}
	for _, files := range chain {
		var st stage
		for _, f := range files {
			d, err := load(f)
			if err != nil {
				return nil, err
			}
			st = append(st, d)
		}
		c.stages = append(c.stages, st)
	}
	return c, nil
}

// load reads an OpenCC text dictionary: "key<TAB>candidate[ candidate...]" per line.
func load(name string) (dict, error) {
	f, err := dictFS.Open("dict/" + name + ".txt")
	if err != nil {
		return dict{}, err
	}
	defer f.Close()
	d := dict{m: map[string]string{}}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), "\t")
		if !ok || k == "" {
			continue
		}
		if i := strings.IndexByte(v, ' '); i >= 0 {
			v = v[:i] // first candidate, as OpenCC does
		}
		d.m[k] = v // a key listed twice: the later line wins, as in longbridgeapp/opencc
		if n := len([]rune(k)); n > d.maxLen {
			d.maxLen = n
		}
	}
	return d, sc.Err()
}

// Convert runs the whole chain. It never fails; the error is kept for the old call sites.
func (c *Converter) Convert(s string) (string, error) {
	for _, st := range c.stages {
		s = st.apply(s)
	}
	return s, nil
}

// window is how far ahead a match may reach (runes), as in longbridgeapp/opencc v0.3.13.
const window = 10

// apply follows longbridgeapp/opencc v0.3.13 exactly, so file names come out the same as
// before the switch: at each position the FIRST dictionary of the stage that has any key
// prefixing the text wins, and within it the longest such key (within window runes).
func (st stage) apply(s string) string {
	r := []rune(s)
	var b strings.Builder
	for i := 0; i < len(r); {
		end := len(r)
		if end > i+window {
			end = i + window
		}
		n := 0
		var tok string
		for _, d := range st {
			for k := end - i; k >= 1; k-- {
				if k > d.maxLen {
					continue
				}
				if v, ok := d.m[string(r[i:i+k])]; ok {
					n, tok = k, v
					break
				}
			}
			if n > 0 {
				break
			}
		}
		if n == 0 {
			b.WriteRune(r[i])
			i++
			continue
		}
		b.WriteString(tok)
		i += n
	}
	return b.String()
}
