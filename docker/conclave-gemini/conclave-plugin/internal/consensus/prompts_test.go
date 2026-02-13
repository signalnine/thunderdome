package consensus

import (
	"strings"
	"testing"
)

func TestBuildThesisSummaryPrompt(t *testing.T) {
	prompt := BuildThesisSummaryPrompt("This is a long analysis with many points about security...")
	if !strings.Contains(prompt, "2-3 sentence") {
		t.Error("should instruct agent to produce 2-3 sentence summary")
	}
	if !strings.Contains(prompt, "security") {
		t.Error("should include the original analysis text")
	}
}

func TestBuildDebatePrompt(t *testing.T) {
	theses := map[string]string{
		"Claude": "The code has SQL injection vulnerabilities.",
		"Gemini": "The code is secure but has performance issues.",
		"Codex":  "Both security and performance need attention.",
	}
	prompt := BuildDebatePrompt(theses, "claude")

	if !strings.Contains(prompt, "Claude") {
		t.Error("should include Claude's thesis")
	}
	if !strings.Contains(prompt, "Gemini") {
		t.Error("should include Gemini's thesis")
	}
	if !strings.Contains(prompt, "disagreement") || !strings.Contains(prompt, "error") {
		t.Error("should instruct agent to find disagreements and errors")
	}
}

func TestBuildDebateChairmanPrompt(t *testing.T) {
	results := []AgentResult{
		{Agent: "Claude", Output: "Original Claude analysis"},
		{Agent: "Gemini", Output: "Original Gemini analysis"},
	}
	rebuttals := []AgentResult{
		{Agent: "Claude", Output: "Claude's rebuttal of Gemini"},
		{Agent: "Gemini", Output: "Gemini's rebuttal of Claude"},
	}

	prompt := BuildDebateChairmanPrompt("Review this code", results, rebuttals)

	if !strings.Contains(prompt, "Original Claude analysis") {
		t.Error("should include original analyses")
	}
	if !strings.Contains(prompt, "Claude's rebuttal") {
		t.Error("should include rebuttals")
	}
	if !strings.Contains(prompt, "convergence") || !strings.Contains(prompt, "changed") {
		t.Error("should instruct chairman to weigh position changes")
	}
}
