package shortener

import (
	"errors"
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
