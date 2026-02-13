package ralph

func IsStuck(stuckCount, threshold int) bool {
	return stuckCount >= threshold
}

const StuckDirective = `## IMPORTANT: You Are Stuck

You have failed 3+ times with the same error. Your previous approach does not work.

You MUST try a fundamentally different approach:
- Different algorithm or data structure
- Different library or API
- Simplify the problem
- Break into smaller pieces

Do NOT repeat the same approach that failed.
`
