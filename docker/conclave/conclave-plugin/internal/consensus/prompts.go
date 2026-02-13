package consensus

import (
	"fmt"
	"strings"
)

func BuildCodeReviewPrompt(description, diff, modifiedFiles, planContent string) string {
	var b strings.Builder
	b.WriteString("# Code Review - Stage 1 Independent Analysis\n\n")
	b.WriteString("**Your Task:** Independently review these code changes and provide your analysis.\n\n")
	fmt.Fprintf(&b, "**Change Description:** %s\n\n", description)
	fmt.Fprintf(&b, "**Modified Files:**\n%s\n\n", modifiedFiles)

	if planContent != "" {
		fmt.Fprintf(&b, "**Implementation Plan:**\n%s\n\n", planContent)
	}

	fmt.Fprintf(&b, "**Diff:**\n```diff\n%s\n```\n\n", diff)
	b.WriteString(`**Instructions:**
Please provide your independent code review in the following format:

## Critical Issues
- [List critical issues, or write 'None']

## Important Issues
- [List important issues, or write 'None']

## Suggestions
- [List suggestions, or write 'None']

Focus on correctness, security, performance, and adherence to the plan (if provided).
`)
	return b.String()
}

func BuildGeneralPrompt(prompt, context string) string {
	var b strings.Builder
	b.WriteString("# General Analysis - Stage 1 Independent Analysis\n\n")
	b.WriteString("**Your Task:** Independently analyze this question and provide your perspective.\n\n")
	fmt.Fprintf(&b, "**Question:**\n%s\n\n", prompt)

	if context != "" {
		fmt.Fprintf(&b, "**Context:**\n%s\n\n", context)
	}

	b.WriteString(`**Instructions:**
Please provide your independent analysis in the following format:

## Strong Points
- [List strong arguments/points, or write 'None']

## Moderate Points
- [List moderate arguments/points, or write 'None']

## Weak Points / Concerns
- [List weak points or concerns, or write 'None']

Provide thoughtful, independent analysis.
`)
	return b.String()
}

func BuildCodeReviewChairmanPrompt(description, modifiedFiles string, results []AgentResult) string {
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}

	var b strings.Builder
	b.WriteString("# Code Review Consensus - Stage 2 Chairman Synthesis\n\n")
	b.WriteString("**Your Task:** Compile a consensus code review from multiple independent reviewers.\n\n")
	b.WriteString("**CRITICAL:** Report all issues mentioned by any reviewer. Group similar issues together, but if reviewers disagree about an issue, report the disagreement explicitly.\n\n")
	fmt.Fprintf(&b, "**Change Description:** %s\n\n", description)
	fmt.Fprintf(&b, "**Modified Files:**\n%s\n\n", modifiedFiles)
	fmt.Fprintf(&b, "**Reviews Received (%d of 3):**\n\n", succeeded)

	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Review ---\n%s\n\n", r.Agent, r.Output)
		}
	}

	b.WriteString(`**Instructions:**
Compile a consensus report with three tiers:

## High Priority - Multiple Reviewers Agree
[Issues mentioned by 2+ reviewers - group similar issues]

## Medium Priority - Single Reviewer, Significant
[Important/Critical issues from single reviewer]

## Consider - Suggestions
[Suggestions from any reviewer]

## Final Recommendation
- If High Priority issues exist: "Address high priority issues before merging"
- If only Medium Priority: "Review medium priority concerns"
- If only Consider tier: "Optional improvements suggested"
- If no issues: "All reviewers approve - safe to merge"

Be direct. Group similar issues but preserve different perspectives.
`)
	return b.String()
}

func BuildGeneralChairmanPrompt(originalPrompt string, results []AgentResult) string {
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}

	var b strings.Builder
	b.WriteString("# General Analysis Consensus - Stage 2 Chairman Synthesis\n\n")
	b.WriteString("**Your Task:** Compile consensus from multiple independent analyses.\n\n")
	b.WriteString("**CRITICAL:** If analyses disagree or conflict, highlight disagreements explicitly. Do NOT smooth over conflicts.\n\n")
	fmt.Fprintf(&b, "**Original Question:**\n%s\n\n", originalPrompt)
	fmt.Fprintf(&b, "**Analyses Received (%d of 3):**\n\n", succeeded)

	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Analysis ---\n%s\n\n", r.Agent, r.Output)
		}
	}

	b.WriteString(`**Instructions:**
Provide final consensus:

## Areas of Agreement
[What do reviewers agree on?]

## Areas of Disagreement
[Where do perspectives differ? Be explicit about conflicts.]

## Confidence Level
High / Medium / Low

## Synthesized Recommendation
[Incorporate all perspectives, noting disagreements where they exist]

Be direct. Disagreement is valuable - report it clearly.
`)
	return b.String()
}

// BuildThesisSummaryPrompt creates a prompt asking an agent to summarize its analysis.
func BuildThesisSummaryPrompt(analysis string) string {
	return fmt.Sprintf(`Summarize your analysis below in exactly 2-3 sentences. Capture your main position and key findings. Be specific and direct.

Your analysis:
%s`, analysis)
}

// BuildDebatePrompt creates a prompt for the debate round, showing all agents' thesis summaries.
func BuildDebatePrompt(theses map[string]string, selfAgent string) string {
	var b strings.Builder
	b.WriteString("Three agents analyzed this problem independently. Their positions:\n\n")
	for agent, thesis := range theses {
		b.WriteString(fmt.Sprintf("- %s: %q\n", agent, thesis))
	}
	b.WriteString("\nIdentify specific points of disagreement, factual errors, or missing considerations in the other agents' analyses. Be concise and direct. Focus on substance, not style.")
	return b.String()
}

// BuildDebateChairmanPrompt creates the chairman prompt that includes both original analyses and rebuttals.
func BuildDebateChairmanPrompt(originalPrompt string, analyses []AgentResult, rebuttals []AgentResult) string {
	var b strings.Builder
	b.WriteString("You are synthesizing a multi-agent analysis that included a debate round.\n\n")
	b.WriteString(fmt.Sprintf("Original question: %s\n\n", originalPrompt))

	b.WriteString("## Original Analyses\n\n")
	for _, r := range analyses {
		if r.Err == nil {
			b.WriteString(fmt.Sprintf("--- %s Analysis ---\n%s\n\n", r.Agent, r.Output))
		}
	}

	b.WriteString("## Rebuttals (after seeing each other's analyses)\n\n")
	for _, r := range rebuttals {
		if r.Err == nil {
			b.WriteString(fmt.Sprintf("--- %s Rebuttal ---\n%s\n\n", r.Agent, r.Output))
		}
	}

	b.WriteString("Synthesize all findings. Pay special attention to:\n")
	b.WriteString("- Points where agents changed their position after debate — convergence after challenge is a strong signal\n")
	b.WriteString("- Points where agents maintained disagreement despite rebuttals — flag these as genuinely contested\n")
	b.WriteString("- Factual corrections made during the debate round\n\n")
	b.WriteString("Output format:\n## Areas of Agreement\n## Areas of Disagreement\n## Confidence Level\n## Synthesized Recommendation")
	return b.String()
}
