package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadImagesRejectsTag(t *testing.T) {
	path := filepath.Join(t.TempDir(), "api.digest")
	if err := os.WriteFile(path, []byte("latest\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := readImages([]string{"api=" + path}); err == nil {
		t.Error("readImages accepted a tag as a digest")
	}
}

func TestReadImagesSortsByName(t *testing.T) {
	dir := t.TempDir()
	d := "sha256:" + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	for _, n := range []string{"worker", "api"} {
		if err := os.WriteFile(filepath.Join(dir, n), []byte(d+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	images, err := readImages([]string{"worker=" + filepath.Join(dir, "worker"), "api=" + filepath.Join(dir, "api")})
	if err != nil {
		t.Fatal(err)
	}
	if images[0].name != "api" || images[1].name != "worker" {
		t.Errorf("images are not sorted: %v", images)
	}
}
