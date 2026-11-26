// Package counter は短縮コードごとのアクセスの回数を数える。
package counter

import "sync"

// Counter は回数をメモリーに保持する。複数の goroutine から使ってよい。
type Counter struct {
	mu     sync.Mutex
	counts map[string]int64
}

// New は空の Counter を返す。
func New() *Counter {
	return &Counter{counts: make(map[string]int64)}
}

// Add は code の回数を1つ増やし、増やしたあとの回数を返す。
func (c *Counter) Add(code string) int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.counts[code]++
	return c.counts[code]
}

// Get は code の回数を返す。記録がなければ0を返す。
func (c *Counter) Get(code string) int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.counts[code]
}
