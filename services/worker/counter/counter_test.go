package counter

import (
	"sync"
	"testing"
)

func TestAddAndGet(t *testing.T) {
	c := New()
	c.Add("1")
	c.Add("1")
	c.Add("2")
	if got := c.Get("1"); got != 2 {
		t.Errorf("Get(%q) = %d, want 2", "1", got)
	}
	if got := c.Get("3"); got != 0 {
		t.Errorf("Get(%q) = %d, want 0", "3", got)
	}
}

func TestConcurrentAdd(t *testing.T) {
	c := New()
	var wg sync.WaitGroup
	for range 100 {
		wg.Go(func() { c.Add("1") })
	}
	wg.Wait()
	if got := c.Get("1"); got != 100 {
		t.Errorf("Get(%q) = %d, want 100", "1", got)
	}
}
