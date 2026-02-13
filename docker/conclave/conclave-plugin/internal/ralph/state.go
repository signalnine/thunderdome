package ralph

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	stateFileName   = ".ralph_state.json"
	contextFileName = ".ralph_context.md"
)

type Attempt struct {
	Iteration int    `json:"iteration"`
	Gate      string `json:"gate"`
	Hash      string `json:"hash"`
	Shift     bool   `json:"shift"`
}

type State struct {
	TaskID         string    `json:"task_id"`
	Iteration      int       `json:"iteration"`
	MaxIterations  int       `json:"max_iterations"`
	LastGate       string    `json:"last_gate"`
	ExitCode       int       `json:"exit_code"`
	ErrorHash      string    `json:"error_hash"`
	Timestamp      time.Time `json:"timestamp"`
	StuckCount     int       `json:"stuck_count"`
	StrategyShifts int       `json:"strategy_shifts"`
	Attempts       []Attempt `json:"attempts"`
}

type StateManager struct {
	dir string
}

func NewStateManager(dir string) *StateManager {
	return &StateManager{dir: dir}
}

func (s *StateManager) statePath() string   { return filepath.Join(s.dir, stateFileName) }
func (s *StateManager) contextPath() string { return filepath.Join(s.dir, contextFileName) }

func (s *StateManager) Exists() bool {
	_, err := os.Stat(s.statePath())
	return err == nil
}

func (s *StateManager) Init(taskID string, maxIter int) error {
	state := &State{
		TaskID:        taskID,
		Iteration:     1,
		MaxIterations: maxIter,
		Timestamp:     time.Now(),
		Attempts:      []Attempt{},
	}
	if err := s.save(state); err != nil {
		return err
	}
	ctx := fmt.Sprintf("# Ralph Loop Context: %s\n\n## Status\n- Iteration: 1 of %d\n- Last gate: (none yet)\n\n## Previous Output\n(First attempt - no previous output)\n", taskID, maxIter)
	return os.WriteFile(s.contextPath(), []byte(ctx), 0644)
}

func (s *StateManager) Load() (*State, error) {
	data, err := os.ReadFile(s.statePath())
	if err != nil {
		return nil, err
	}
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}
	return &state, nil
}

func (s *StateManager) Update(gate string, exitCode int, output string) error {
	state, err := s.Load()
	if err != nil {
		return err
	}

	// Hash first 20 lines of output
	lines := strings.Split(output, "\n")
	if len(lines) > 20 {
		lines = lines[:20]
	}
	hash := fmt.Sprintf("%x", md5.Sum([]byte(strings.Join(lines, "\n"))))

	// Stuck detection
	if hash == state.ErrorHash && state.ErrorHash != "" {
		state.StuckCount++
	} else {
		state.StuckCount = 0
	}

	// Truncate output
	truncated := output
	allLines := strings.Split(output, "\n")
	if len(allLines) > 100 {
		truncated = strings.Join(allLines[:100], "\n") +
			fmt.Sprintf("\n[... truncated, %d total lines ...]", len(allLines))
	}

	state.Attempts = append(state.Attempts, Attempt{
		Iteration: state.Iteration,
		Gate:      gate,
		Hash:      hash[:8],
		Shift:     state.StrategyShifts > 0,
	})
	state.Iteration++
	state.LastGate = gate
	state.ExitCode = exitCode
	state.ErrorHash = hash
	state.Timestamp = time.Now()

	if err := s.save(state); err != nil {
		return err
	}

	// Update context file
	ctx := fmt.Sprintf("# Ralph Loop Context: %s\n\n## Status\n- Iteration: %d of %d\n- Last gate failed: %s\n- Stuck count: %d (threshold: 3)\n\n## Last Error Output (verbatim)\n```\n%s\n```\n",
		state.TaskID, state.Iteration, state.MaxIterations, gate, state.StuckCount, truncated)
	return os.WriteFile(s.contextPath(), []byte(ctx), 0644)
}

func (s *StateManager) IncrementStrategyShift() error {
	state, err := s.Load()
	if err != nil {
		return err
	}
	state.StrategyShifts++
	return s.save(state)
}

func (s *StateManager) Cleanup() {
	os.Remove(s.statePath())
	os.Remove(s.contextPath())
}

func (s *StateManager) save(state *State) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.statePath(), data, 0644)
}

func (s *StateManager) ContextFile() string { return s.contextPath() }
