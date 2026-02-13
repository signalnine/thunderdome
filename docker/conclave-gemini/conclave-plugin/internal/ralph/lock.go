package ralph

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

const lockFileName = ".ralph.lock"

type Lock struct {
	dir string
}

func NewLock(dir string) *Lock {
	return &Lock{dir: dir}
}

func (l *Lock) path() string { return filepath.Join(l.dir, lockFileName) }

func (l *Lock) Acquire() error {
	data, err := os.ReadFile(l.path())
	if err == nil {
		pid, _ := strconv.Atoi(string(data))
		if pid > 0 {
			if err := syscall.Kill(pid, 0); err == nil {
				return fmt.Errorf("another Ralph loop is active (PID %d)", pid)
			}
		}
		fmt.Fprintf(os.Stderr, "WARNING: Removing stale lock (PID %d no longer running)\n", pid)
		os.Remove(l.path())
	}
	return os.WriteFile(l.path(), []byte(strconv.Itoa(os.Getpid())), 0644)
}

func (l *Lock) Release() {
	os.Remove(l.path())
}
