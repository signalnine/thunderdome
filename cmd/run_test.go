package cmd

import (
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
)

func TestFilterOrchestrators(t *testing.T) {
	orchs := []config.Orchestrator{
		{Name: "alpha", Adapter: "a.sh", Image: "img-a"},
		{Name: "beta", Adapter: "b.sh", Image: "img-b"},
		{Name: "gamma", Adapter: "g.sh", Image: "img-g"},
	}

	tests := []struct {
		name   string
		filter string
		want   int
	}{
		{"empty filter returns all", "", 3},
		{"exact match", "beta", 1},
		{"no match", "delta", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := filterOrchestrators(orchs, tt.filter)
			if len(got) != tt.want {
				t.Errorf("filterOrchestrators(%q) returned %d, want %d", tt.filter, len(got), tt.want)
			}
		})
	}
}

func TestFilterTasks(t *testing.T) {
	tasks := []config.Task{
		{Repo: "github.com/org/foo", Tag: "v1", Category: "greenfield/simple", ValidationImage: "img", TestCmd: "test"},
		{Repo: "github.com/org/bar", Tag: "v1", Category: "greenfield/complex", ValidationImage: "img", TestCmd: "test"},
		{Repo: "github.com/org/baz", Tag: "v1", Category: "bugfix/simple", ValidationImage: "img", TestCmd: "test"},
	}

	tests := []struct {
		name     string
		nameF    string
		catF     string
		want     int
	}{
		{"empty filters returns all", "", "", 3},
		{"filter by full repo name", "github.com/org/foo", "", 1},
		{"filter by short name", "bar", "", 1},
		{"filter by exact category", "", "bugfix/simple", 1},
		{"filter by category wildcard", "", "greenfield/*", 2},
		{"no match by name", "nonexistent", "", 0},
		{"no match by category", "", "marathon/simple", 0},
		{"combined name and category", "foo", "greenfield/simple", 1},
		{"combined name and wrong category", "foo", "bugfix/simple", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := filterTasks(tasks, tt.nameF, tt.catF)
			if len(got) != tt.want {
				t.Errorf("filterTasks(name=%q, cat=%q) returned %d, want %d", tt.nameF, tt.catF, len(got), tt.want)
			}
		})
	}
}

func TestMatchCategory(t *testing.T) {
	tests := []struct {
		name     string
		category string
		pattern  string
		want     bool
	}{
		{"exact match", "greenfield/simple", "greenfield/simple", true},
		{"exact mismatch", "greenfield/simple", "greenfield/complex", false},
		{"wildcard match", "greenfield/simple", "greenfield/*", true},
		{"wildcard mismatch", "bugfix/simple", "greenfield/*", false},
		{"empty category", "", "greenfield/*", false},
		{"empty pattern exact", "", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := matchCategory(tt.category, tt.pattern)
			if got != tt.want {
				t.Errorf("matchCategory(%q, %q) = %v, want %v", tt.category, tt.pattern, got, tt.want)
			}
		})
	}
}

func TestTimeoutForTask(t *testing.T) {
	tests := []struct {
		name string
		task config.Task
		want time.Duration
	}{
		{"explicit time limit", config.Task{Category: "greenfield/simple", TimeLimitMinutes: 15}, 15 * time.Minute},
		{"explicit overrides category", config.Task{Category: "marathon/long", TimeLimitMinutes: 25}, 25 * time.Minute},
		{"fallback marathon", config.Task{Category: "marathon/long"}, 60 * time.Minute},
		{"fallback complex", config.Task{Category: "greenfield/complex"}, 30 * time.Minute},
		{"fallback simple", config.Task{Category: "greenfield/simple"}, 10 * time.Minute},
		{"fallback bugfix", config.Task{Category: "bugfix/medium"}, 10 * time.Minute},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := timeoutForTask(&tt.task)
			if got != tt.want {
				t.Errorf("timeoutForTask(%+v) = %v, want %v", tt.task, got, tt.want)
			}
		})
	}
}
