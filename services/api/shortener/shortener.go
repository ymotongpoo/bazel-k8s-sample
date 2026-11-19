// Package shortener は短縮コードと元の URL の対応を保持する。
package shortener

import (
	"errors"
	"strconv"
	"sync"
)

// ErrNotFound は、登録されていないコードを引いたときに返す。
var ErrNotFound = errors.New("shortener: code not found")

// Store は対応をメモリーに保持する。複数の goroutine から使ってよい。
type Store struct {
	mu   sync.RWMutex
	next uint64
	urls map[string]string
}

// NewStore は空の Store を返す。
func NewStore() *Store {
	return &Store{next: 1, urls: make(map[string]string)}
}

// Shorten は url に新しいコードを割り当てて返す。
// コードは連番を 36 進数で表したもの。
func (s *Store) Shorten(url string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	code := strconv.FormatUint(s.next, 36)
	s.next++
	s.urls[code] = url
	return code
}

// Resolve は code に対応する URL を返す。
func (s *Store) Resolve(code string) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	url, ok := s.urls[code]
	if !ok {
		return "", ErrNotFound
	}
	return url, nil
}
