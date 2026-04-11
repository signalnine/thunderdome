#!/usr/bin/env bash
set -euo pipefail

# Test real-world timing for multi-agent consensus
# This script measures actual execution times with various prompt complexities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSENSUS_SCRIPT="$SCRIPT_DIR/consensus-synthesis.sh"
RESULTS_FILE="$SCRIPT_DIR/timing-results-$(date +%Y%m%d-%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🧪 Real-World Timing Tests for Multi-Agent Consensus"
echo "======================================================"
echo ""
echo "Results will be saved to: $RESULTS_FILE"
echo ""

# Initialize results file
cat > "$RESULTS_FILE" <<EOF
{
  "test_run": "$(date -Iseconds)",
  "tests": []
}
EOF

# Function to add test result to JSON
add_result() {
    local test_name="$1"
    local duration="$2"
    local stage1_time="$3"
    local stage2_time="$4"
    local success="$5"
    local agent_count="$6"
    local timeout_hit="$7"

    # Read current JSON
    local current=$(cat "$RESULTS_FILE")

    # Create new test entry
    local new_test=$(cat <<EOJSON
{
  "test_name": "$test_name",
  "total_duration_seconds": $duration,
  "stage1_duration_seconds": $stage1_time,
  "stage2_duration_seconds": $stage2_time,
  "success": $success,
  "agents_completed": $agent_count,
  "timeout_hit": $timeout_hit
}
EOJSON
)

    # Append to tests array (simple approach - rebuild JSON)
    local tests=$(echo "$current" | jq ".tests += [$new_test]")
    echo "$tests" > "$RESULTS_FILE"
}

# Function to run timed test
run_timed_test() {
    local test_name="$1"
    local mode="$2"
    local prompt="$3"
    local timeout_override="${4:-90}" # Default 90s to see if 30s is really the problem

    echo -e "${BLUE}▶ Test: $test_name${NC}"
    echo "  Mode: $mode"
    echo "  Prompt: ${prompt:0:80}..."
    echo "  Timeout: ${timeout_override}s"
    echo ""

    local start_time=$(date +%s.%N)
    local output
    local exit_code=0

    # Temporarily modify timeout in consensus script for this test
    local temp_script=$(mktemp)
    sed "s/local timeout_duration=30/local timeout_duration=$timeout_override/" "$CONSENSUS_SCRIPT" > "$temp_script"
    chmod +x "$temp_script"

    # Run with extended timeout to capture full execution
    output=$(timeout 120s bash "$temp_script" --mode="$mode" --prompt="$prompt" 2>&1) || exit_code=$?

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    rm -f "$temp_script"

    # Parse output for timing info
    local stage1_time=0
    local stage2_time=0
    local agent_count=0
    local timeout_hit="false"
    local success="false"

    # Extract stage 1 timing (look for agent completion messages)
    if echo "$output" | grep -q "Stage 1 complete"; then
        # Count successful agents
        agent_count=$(echo "$output" | grep -c "Agent.*completed" || echo "0")
    fi

    # Check for timeout
    if echo "$output" | grep -q "Timeout reached\|TIMEOUT"; then
        timeout_hit="true"
    fi

    # Check for success (consensus report generated)
    if echo "$output" | grep -q "CONSENSUS REPORT\|unanimous\|majority\|split"; then
        success="true"
        echo -e "  ${GREEN}✓ Success${NC}"
    else
        echo -e "  ${RED}✗ Failed or timed out${NC}"
    fi

    # Estimate stage times from output
    # This is approximate - real implementation would need instrumentation
    if [[ "$success" == "true" ]]; then
        # Rough estimate: 60/40 split between stages
        stage1_time=$(echo "$duration * 0.6" | bc)
        stage2_time=$(echo "$duration * 0.4" | bc)
    else
        stage1_time="$duration"
        stage2_time="0"
    fi

    echo "  Duration: ${duration}s"
    echo "  Stage 1 (est): ${stage1_time}s"
    echo "  Stage 2 (est): ${stage2_time}s"
    echo "  Agents completed: $agent_count"
    echo "  Timeout hit: $timeout_hit"
    echo ""

    add_result "$test_name" "$duration" "$stage1_time" "$stage2_time" "$success" "$agent_count" "$timeout_hit"
}

# Test cases with varying complexity

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 1: Simple Prompts (Expected: <15s)"
echo "═══════════════════════════════════════════════════════"
echo ""

run_timed_test \
    "Simple code review - short function" \
    "code-review" \
    "function add(a, b) { return a + b; }"

run_timed_test \
    "Simple general prompt" \
    "general-prompt" \
    "What are the best practices for naming variables in Python?"

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 2: Medium Complexity (Expected: 15-30s)"
echo "═══════════════════════════════════════════════════════"
echo ""

run_timed_test \
    "Medium code review - class with methods" \
    "code-review" \
    "$(cat <<'EOF'
class UserManager {
    constructor(db) {
        this.db = db;
        this.cache = new Map();
    }

    async getUser(id) {
        if (this.cache.has(id)) {
            return this.cache.get(id);
        }
        const user = await this.db.query('SELECT * FROM users WHERE id = ?', [id]);
        this.cache.set(id, user);
        return user;
    }

    async createUser(data) {
        const result = await this.db.insert('users', data);
        return result.insertId;
    }
}
EOF
)"

run_timed_test \
    "Medium plan review - multi-step implementation" \
    "plan-review" \
    "$(cat <<'EOF'
# Implementation Plan: Add User Authentication

## Tasks
1. Create database migration for users table
2. Implement password hashing with bcrypt
3. Create login endpoint with JWT generation
4. Create middleware to verify JWT tokens
5. Add protected routes
6. Write unit tests for auth logic
7. Add integration tests for endpoints
EOF
)"

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 3: High Complexity (Expected: 30-60s?)"
echo "═══════════════════════════════════════════════════════"
echo ""

run_timed_test \
    "Complex code review - full module" \
    "code-review" \
    "$(cat <<'EOF'
// API Gateway with rate limiting, caching, and circuit breaker
class APIGateway {
    constructor(config) {
        this.routes = new Map();
        this.rateLimit = new RateLimiter(config.rateLimit);
        this.cache = new Cache(config.cache);
        this.circuitBreaker = new CircuitBreaker(config.circuitBreaker);
        this.metrics = new MetricsCollector();
    }

    registerRoute(path, handler, options = {}) {
        this.routes.set(path, {
            handler,
            auth: options.auth || false,
            rateLimit: options.rateLimit || this.rateLimit.defaultLimit,
            cache: options.cache || false,
            timeout: options.timeout || 30000
        });
    }

    async handleRequest(req, res) {
        const route = this.routes.get(req.path);
        if (!route) {
            return this.notFound(res);
        }

        // Rate limiting
        if (!await this.rateLimit.check(req.ip, route.rateLimit)) {
            return this.rateExceeded(res);
        }

        // Check cache
        if (route.cache && req.method === 'GET') {
            const cached = await this.cache.get(req.path);
            if (cached) {
                this.metrics.recordCacheHit(req.path);
                return this.send(res, cached);
            }
        }

        // Circuit breaker
        if (!this.circuitBreaker.isAvailable(req.path)) {
            return this.serviceUnavailable(res);
        }

        try {
            const result = await Promise.race([
                route.handler(req),
                this.timeout(route.timeout)
            ]);

            this.circuitBreaker.recordSuccess(req.path);

            if (route.cache && req.method === 'GET') {
                await this.cache.set(req.path, result);
            }

            this.metrics.recordSuccess(req.path);
            return this.send(res, result);
        } catch (error) {
            this.circuitBreaker.recordFailure(req.path);
            this.metrics.recordError(req.path, error);
            return this.error(res, error);
        }
    }
}
EOF
)"

run_timed_test \
    "Complex architectural decision" \
    "general-prompt" \
    "$(cat <<'EOF'
We need to design a distributed caching system for a microservices architecture.
Requirements:
- Handle 100k requests per second
- Sub-10ms latency for cache hits
- Automatic cache invalidation across services
- Support for both read-through and write-through patterns
- Multi-region deployment with eventual consistency
- Cost-effective for 1TB of cached data

What architecture would you recommend? Consider:
1. Cache topology (distributed, replicated, partitioned)
2. Consistency model and trade-offs
3. Invalidation strategy
4. Technology choices (Redis, Memcached, etc.)
5. Monitoring and observability
6. Failure scenarios and recovery
EOF
)"

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 4: Stress Test (Expected: May timeout at 30s)"
echo "═══════════════════════════════════════════════════════"
echo ""

# Generate a very long code review (simulate real PR with multiple files)
LARGE_CODE=""
for i in {1..5}; do
    LARGE_CODE+="
// File $i: service-$i.js
class Service$i {
    constructor(deps) { this.deps = deps; }
    async process(data) {
        const validated = this.validate(data);
        const transformed = await this.transform(validated);
        return this.store(transformed);
    }
    validate(data) { return data; }
    async transform(data) { return data; }
    async store(data) { return true; }
}
"
done

run_timed_test \
    "Stress test - multiple files" \
    "code-review" \
    "$LARGE_CODE"

echo ""
echo "════════════════════════════════════════════════════════"
echo "TEST COMPLETE"
echo "════════════════════════════════════════════════════════"
echo ""

# Generate summary
echo "📊 Summary Statistics"
echo "═══════════════════════════════════════════════════════"
echo ""

jq -r '
.tests |
"Total tests: \(length)",
"Successful: \([.[] | select(.success == true)] | length)",
"Failed: \([.[] | select(.success == false)] | length)",
"Timeouts: \([.[] | select(.timeout_hit == true)] | length)",
"",
"Duration Statistics:",
"  Min: \([.[].total_duration_seconds] | min)s",
"  Max: \([.[].total_duration_seconds] | max)s",
"  Avg: \(([.[].total_duration_seconds] | add / length) | . * 100 | round / 100)s",
"  Median: \([.[].total_duration_seconds] | sort | if length % 2 == 0 then (.[length/2 - 1] + .[length/2]) / 2 else .[length/2 | floor] end)s",
"",
"Tests exceeding 30s:",
([.[] | select(.total_duration_seconds > 30)] |
  if length > 0 then
    map("  - \(.test_name): \(.total_duration_seconds)s") | join("\n")
  else
    "  None"
  end)
' "$RESULTS_FILE"

echo ""
echo "Full results saved to: $RESULTS_FILE"
echo ""
echo "💡 Recommendations:"
echo "═══════════════════════════════════════════════════════"

# Calculate recommended timeout
RECOMMENDED_TIMEOUT=$(jq -r '
([.tests[].total_duration_seconds] | max) as $max |
if $max > 60 then 90
elif $max > 40 then 60
elif $max > 30 then 45
else 30
end
' "$RESULTS_FILE")

PERCENTILE_95=$(jq -r '
[.tests[].total_duration_seconds] | sort |
.[length * 0.95 | floor]
' "$RESULTS_FILE")

echo "95th percentile completion time: ${PERCENTILE_95}s"
echo "Current timeout: 30s"
echo "Recommended timeout: ${RECOMMENDED_TIMEOUT}s"
echo ""

if (( $(echo "$PERCENTILE_95 > 30" | bc -l) )); then
    echo -e "${YELLOW}⚠ WARNING: 30s timeout is too short!${NC}"
    echo "   Some tests would fail with current timeout settings."
else
    echo -e "${GREEN}✓ Current 30s timeout appears adequate${NC}"
    echo "   Consider adding buffer for network variability."
fi

echo ""
echo "Review the full timing data in $RESULTS_FILE for detailed analysis."
