package shortener

import (
	"errors"
	"sync"
	"testing"
)

func TestShortenAndResolve(t *testing.T) {
	s := NewStore()
	code := s.Shorten("https://example.com/")
	got, err := s.Resolve(code)
	if err != nil {
		t.Fatalf("Resolve(%q) returned error: %v", code, err)
	}
	if got != "https://example.com/" {
		t.Errorf("Resolve(%q) = %q, want %q", code, got, "https://example.com/")
	}
}

func TestResolveUnknownCode(t *testing.T) {
	s := NewStore()
	if _, err := s.Resolve("zzz"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Resolve(%q) error = %v, want ErrNotFound", "zzz", err)
	}
}

func TestShortenReturnsDistinctCodes(t *testing.T) {
	s := NewStore()
	a := s.Shorten("https://example.com/a")
	b := s.Shorten("https://example.com/a")
	if a == b {
		t.Errorf("Shorten returned the same code %q twice", a)
	}
}

func TestCodesAreBase36(t *testing.T) {
	s := NewStore()
	var got []string
	for range 37 {
		got = append(got, s.Shorten("https://example.com/"))
	}
	for i, want := range map[int]string{0: "1", 8: "9", 9: "a", 34: "z", 35: "10", 36: "11"} {
		if got[i] != want {
			t.Errorf("code #%d = %q, want %q", i+1, got[i], want)
		}
	}
}

func TestConcurrentShorten(t *testing.T) {
	s := NewStore()
	const n = 100
	codes := make(chan string, n)
	var wg sync.WaitGroup
	for range n {
		wg.Go(func() {
			codes <- s.Shorten("https://example.com/")
		})
	}
	wg.Wait()
	close(codes)
	seen := make(map[string]bool)
	for c := range codes {
		if seen[c] {
			t.Fatalf("code %q was issued twice", c)
		}
		seen[c] = true
	}
}
