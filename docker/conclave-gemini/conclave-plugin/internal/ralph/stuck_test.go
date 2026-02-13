package ralph

import (
	"testing"
)

func TestIsStuck(t *testing.T) {
	tests := []struct {
		name       string
		stuckCount int
		threshold  int
		want       bool
	}{
		{"below threshold", 1, 3, false},
		{"at threshold", 3, 3, true},
		{"above threshold", 5, 3, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsStuck(tt.stuckCount, tt.threshold); got != tt.want {
				t.Errorf("IsStuck(%d, %d) = %v, want %v", tt.stuckCount, tt.threshold, got, tt.want)
			}
		})
	}
}
