package consensus

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

type AgentResult struct {
	Agent  string
	Output string
	Err    error
}

type ConsensusResult struct {
	Stage1Results   []AgentResult
	Rebuttals       []AgentResult
	ChairmanName    string
	ChairmanOutput  string
	OutputFile      string
	AgentsSucceeded int
}

func RunStage1(ctx context.Context, agents []Agent) []AgentResult {
	results := make([]AgentResult, len(agents))
	var wg sync.WaitGroup

	for i, agent := range agents {
		wg.Add(1)
		go func(i int, a Agent) {
			defer wg.Done()
			output, err := a.Run(ctx, "")
			results[i] = AgentResult{Agent: a.Name(), Output: output, Err: err}
		}(i, agent)
	}

	wg.Wait()
	return results
}

func runStage1WithPrompt(ctx context.Context, agents []Agent, prompt string) []AgentResult {
	results := make([]AgentResult, len(agents))
	var wg sync.WaitGroup

	for i, agent := range agents {
		wg.Add(1)
		go func(i int, a Agent) {
			defer wg.Done()
			output, err := a.Run(ctx, prompt)
			results[i] = AgentResult{Agent: a.Name(), Output: output, Err: err}
		}(i, agent)
	}

	wg.Wait()
	return results
}

func RunStage2(ctx context.Context, chairmen []Agent, prompt string) (AgentResult, error) {
	for _, chairman := range chairmen {
		if !chairman.Available() {
			continue
		}
		output, err := chairman.Run(ctx, prompt)
		if err == nil && output != "" {
			return AgentResult{Agent: chairman.Name(), Output: output}, nil
		}
		fmt.Fprintf(os.Stderr, "  %s: FAILED (%v)\n", chairman.Name(), err)
	}
	return AgentResult{}, fmt.Errorf("all chairman agents failed")
}

func RunConsensus(ctx context.Context, agents, chairmen []Agent, prompt string, stage1Timeout, stage2Timeout int) (*ConsensusResult, error) {
	// Filter available agents
	var available []Agent
	for _, a := range agents {
		if a.Available() {
			available = append(available, a)
		}
	}
	if len(available) == 0 {
		return nil, fmt.Errorf("no agents available (need at least 1 API key)")
	}

	// Stage 1
	fmt.Fprintln(os.Stderr, "Stage 1: Launching parallel agent analysis...")
	ctx1, cancel1 := context.WithTimeout(ctx, time.Duration(stage1Timeout)*time.Second)
	defer cancel1()

	fmt.Fprintf(os.Stderr, "  Waiting for agents (%ds timeout)...\n", stage1Timeout)
	start1 := time.Now()
	results := runStage1WithPrompt(ctx1, available, prompt)
	fmt.Fprintf(os.Stderr, "  Stage 1 duration: %.1fs\n", time.Since(start1).Seconds())

	// Tally results
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", r.Agent)
			succeeded++
		} else {
			fmt.Fprintf(os.Stderr, "  %s: FAILED (%v)\n", r.Agent, r.Err)
		}
	}
	fmt.Fprintf(os.Stderr, "  Agents completed: %d/%d succeeded\n", succeeded, len(available))
	if succeeded == 0 {
		return nil, fmt.Errorf("all agents failed (0/%d succeeded)", len(available))
	}

	// Stage 2
	fmt.Fprintln(os.Stderr, "\nStage 2: Chairman synthesis...")
	ctx2, cancel2 := context.WithTimeout(ctx, time.Duration(stage2Timeout)*time.Second)
	defer cancel2()

	chairmanPrompt := buildChairmanPrompt(prompt, results)
	start2 := time.Now()
	chairResult, err := RunStage2(ctx2, chairmen, chairmanPrompt)
	if err != nil {
		return nil, fmt.Errorf("stage 2 failed: %w", err)
	}
	fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", chairResult.Agent)
	fmt.Fprintf(os.Stderr, "  Stage 2 duration: %.1fs\n", time.Since(start2).Seconds())

	return &ConsensusResult{
		Stage1Results:   results,
		ChairmanName:    chairResult.Agent,
		ChairmanOutput:  chairResult.Output,
		AgentsSucceeded: succeeded,
	}, nil
}

// RunConsensusWithBuilder is like RunConsensus but accepts a function to build
// the chairman prompt from stage 1 results (allowing mode-specific prompt building).
func RunConsensusWithBuilder(ctx context.Context, agents, chairmen []Agent, stage1Prompt string, buildChairman func([]AgentResult) string, stage1Timeout, stage2Timeout int) (*ConsensusResult, error) {
	// Filter available agents
	var available []Agent
	for _, a := range agents {
		if a.Available() {
			available = append(available, a)
		}
	}
	if len(available) == 0 {
		return nil, fmt.Errorf("no agents available (need at least 1 API key)")
	}

	// Stage 1
	fmt.Fprintln(os.Stderr, "Stage 1: Launching parallel agent analysis...")
	ctx1, cancel1 := context.WithTimeout(ctx, time.Duration(stage1Timeout)*time.Second)
	defer cancel1()

	fmt.Fprintf(os.Stderr, "  Waiting for agents (%ds timeout)...\n", stage1Timeout)
	start1 := time.Now()
	results := runStage1WithPrompt(ctx1, available, stage1Prompt)
	fmt.Fprintf(os.Stderr, "  Stage 1 duration: %.1fs\n", time.Since(start1).Seconds())

	// Tally results
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", r.Agent)
			succeeded++
		} else {
			fmt.Fprintf(os.Stderr, "  %s: FAILED (%v)\n", r.Agent, r.Err)
		}
	}
	fmt.Fprintf(os.Stderr, "  Agents completed: %d/%d succeeded\n", succeeded, len(available))
	if succeeded == 0 {
		return nil, fmt.Errorf("all agents failed (0/%d succeeded)", len(available))
	}

	// Stage 2
	fmt.Fprintln(os.Stderr, "\nStage 2: Chairman synthesis...")
	ctx2, cancel2 := context.WithTimeout(ctx, time.Duration(stage2Timeout)*time.Second)
	defer cancel2()

	chairmanPrompt := buildChairman(results)
	start2 := time.Now()
	chairResult, err := RunStage2(ctx2, chairmen, chairmanPrompt)
	if err != nil {
		return nil, fmt.Errorf("stage 2 failed: %w", err)
	}
	fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", chairResult.Agent)
	fmt.Fprintf(os.Stderr, "  Stage 2 duration: %.1fs\n", time.Since(start2).Seconds())

	return &ConsensusResult{
		Stage1Results:   results,
		ChairmanName:    chairResult.Agent,
		ChairmanOutput:  chairResult.Output,
		AgentsSucceeded: succeeded,
	}, nil
}

func buildChairmanPrompt(originalPrompt string, results []AgentResult) string {
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Compile consensus from %d of %d analyses.\n\n", succeeded, len(results))
	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Analysis ---\n%s\n\n", r.Agent, r.Output)
		}
	}
	return b.String()
}

// truncateToSentences returns the first n sentences of text.
func truncateToSentences(text string, n int) string {
	count := 0
	for i, c := range text {
		if c == '.' || c == '!' || c == '?' {
			count++
			if count >= n {
				return text[:i+1]
			}
		}
	}
	return text
}

// RunDebateRound executes Stage 1.5: agents see each other's thesis summaries and produce rebuttals.
func RunDebateRound(ctx context.Context, agents []Agent, stage1Results []AgentResult, timeoutSec int) ([]AgentResult, error) {
	theses := make(map[string]string)
	for _, r := range stage1Results {
		if r.Err == nil && r.Output != "" {
			theses[r.Agent] = truncateToSentences(r.Output, 3)
		}
	}

	if len(theses) < 2 {
		return nil, fmt.Errorf("need at least 2 successful Stage 1 results for debate, got %d", len(theses))
	}

	debateCtx, cancel := context.WithTimeout(ctx, time.Duration(timeoutSec)*time.Second)
	defer cancel()

	fmt.Fprintf(os.Stderr, "\n  Stage 1.5: Debate round (%d agents)...\n", len(agents))

	rebuttals := make([]AgentResult, len(agents))
	var wg sync.WaitGroup

	for i, agent := range agents {
		if !agent.Available() {
			rebuttals[i] = AgentResult{Agent: agent.Name(), Err: fmt.Errorf("not available")}
			continue
		}
		wg.Add(1)
		go func(i int, a Agent) {
			defer wg.Done()
			prompt := BuildDebatePrompt(theses, a.Name())
			output, err := a.Run(debateCtx, prompt)
			rebuttals[i] = AgentResult{Agent: a.Name(), Output: output, Err: err}
			if err != nil {
				fmt.Fprintf(os.Stderr, "  %s: DEBATE FAILED (%v)\n", a.Name(), err)
			} else {
				fmt.Fprintf(os.Stderr, "  %s: DEBATE SUCCESS\n", a.Name())
			}
		}(i, agent)
	}
	wg.Wait()

	return rebuttals, nil
}

// RunConsensusWithDebate runs the full consensus flow with an optional debate round.
func RunConsensusWithDebate(ctx context.Context, agents, chairmen []Agent,
	stage1Prompt string,
	buildChairman func([]AgentResult, []AgentResult) string,
	stage1Timeout, debateTimeout, stage2Timeout int,
	debateRounds int) (*ConsensusResult, error) {

	var available []Agent
	for _, a := range agents {
		if a.Available() {
			available = append(available, a)
		}
	}
	if len(available) == 0 {
		return nil, fmt.Errorf("no agents available")
	}

	// Stage 1
	fmt.Fprintf(os.Stderr, "Stage 1: Launching parallel agent analysis...\n")
	ctx1, cancel1 := context.WithTimeout(ctx, time.Duration(stage1Timeout)*time.Second)
	defer cancel1()
	stage1Results := runStage1WithPrompt(ctx1, available, stage1Prompt)

	succeeded := 0
	for _, r := range stage1Results {
		if r.Err == nil {
			succeeded++
		}
	}
	if succeeded == 0 {
		return nil, fmt.Errorf("all agents failed in Stage 1")
	}

	// Stage 1.5: Debate
	var rebuttals []AgentResult
	for round := 0; round < debateRounds; round++ {
		fmt.Fprintf(os.Stderr, "  Debate round %d of %d...\n", round+1, debateRounds)
		var err error
		rebuttals, err = RunDebateRound(ctx, available, stage1Results, debateTimeout)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  Debate round failed: %v (continuing to synthesis)\n", err)
			break
		}
	}

	// Stage 2
	fmt.Fprintf(os.Stderr, "\nStage 2: Chairman synthesis...\n")
	chairmanPrompt := buildChairman(stage1Results, rebuttals)

	ctx2, cancel2 := context.WithTimeout(ctx, time.Duration(stage2Timeout)*time.Second)
	defer cancel2()

	chairmanResult, err := RunStage2(ctx2, chairmen, chairmanPrompt)
	if err != nil {
		return nil, fmt.Errorf("stage 2: %w", err)
	}

	return &ConsensusResult{
		Stage1Results:   stage1Results,
		Rebuttals:       rebuttals,
		ChairmanName:    chairmanResult.Agent,
		ChairmanOutput:  chairmanResult.Output,
		AgentsSucceeded: succeeded,
	}, nil
}
