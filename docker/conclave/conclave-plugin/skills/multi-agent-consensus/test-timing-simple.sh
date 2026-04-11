#!/usr/bin/env bash
set -euo pipefail

# Simple real-world timing test for multi-agent consensus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSENSUS_SCRIPT="$SCRIPT_DIR/consensus-synthesis.sh"

echo "🧪 Real-World Timing Test for Multi-Agent Consensus"
echo "====================================================="
echo ""

# Function to run a single timed test
run_test() {
    local test_name="$1"
    local mode="$2"
    local prompt="$3"

    echo "Test: $test_name"
    echo "Mode: $mode"
    echo ""

    local start=$(date +%s.%N)

    # Run consensus and capture full output
    local output
    output=$(bash "$CONSENSUS_SCRIPT" --mode="$mode" --prompt="$prompt" 2>&1 || true)

    local end=$(date +%s.%N)
    local total_duration=$(echo "$end - $start" | bc)

    # Extract stage durations from output
    local stage1_duration=$(echo "$output" | grep "Stage 1 duration:" | sed 's/.*: \([0-9.]*\)s/\1/' || echo "N/A")
    local stage2_duration=$(echo "$output" | grep "Stage 2 duration:" | sed 's/.*: \([0-9.]*\)s/\1/' || echo "N/A")

    # Check if successful
    local success="FAILED"
    if echo "$output" | grep -q "CONSENSUS COMPLETE"; then
        success="SUCCESS"
    fi

    # Check if timeout was hit
    local timeout_status="No"
    if echo "$output" | grep -q "Timeout reached\|TIMEOUT"; then
        timeout_status="YES"
    fi

    # Display results
    echo "Status: $success"
    echo "Total duration: ${total_duration}s"
    echo "Stage 1 duration: ${stage1_duration}s"
    echo "Stage 2 duration: ${stage2_duration}s"
    echo "Timeout hit: $timeout_status"
    echo ""
    echo "────────────────────────────────────────────────────"
    echo ""

    # Log to CSV for easy analysis
    echo "$test_name,$mode,$total_duration,$stage1_duration,$stage2_duration,$success,$timeout_status" >> timing-results.csv
}

# Initialize CSV
echo "test_name,mode,total_duration,stage1_duration,stage2_duration,success,timeout_hit" > timing-results.csv

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 1: Simple Prompts"
echo "═══════════════════════════════════════════════════════"
echo ""

run_test \
    "Simple general question" \
    "general-prompt" \
    "What are best practices for error handling in JavaScript?"

run_test \
    "Simple code analysis" \
    "general-prompt" \
    "Review this code for potential issues: function fibonacci(n) { if (n <= 1) return n; return fibonacci(n-1) + fibonacci(n-2); }"

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 2: Medium Complexity"
echo "═══════════════════════════════════════════════════════"
echo ""

run_test \
    "Medium code analysis - class" \
    "general-prompt" \
    "$(cat <<'EOF'
Review this code for potential issues, bugs, and improvements:
EOF
)"

run_test \
    "Medium code analysis - class detailed" \
    "general-prompt" \
    "$(cat <<'EOF'
Analyze the following code for bugs, performance issues, and best practices:

class DataProcessor {
    constructor(config) {
        this.config = config;
        this.cache = new Map();
    }

    async process(data) {
        const validated = this.validate(data);
        const transformed = await this.transform(validated);
        const cached = this.cacheResult(transformed);
        return cached;
    }

    validate(data) {
        if (!data || typeof data !== 'object') {
            throw new Error('Invalid data');
        }
        return data;
    }

    async transform(data) {
        // Some async transformation
        return { ...data, processed: true };
    }

    cacheResult(data) {
        const key = JSON.stringify(data);
        this.cache.set(key, data);
        return data;
    }
}
EOF
)"

run_test \
    "Medium architectural question" \
    "general-prompt" \
    "$(cat <<'EOF'
We are building a real-time notification system that needs to:
1. Handle 10,000 concurrent WebSocket connections
2. Support message broadcasting to specific user groups
3. Ensure message delivery guarantees
4. Scale horizontally

What architecture would you recommend? Consider message brokers,
connection management, and failure handling.
EOF
)"

echo "═══════════════════════════════════════════════════════"
echo "TEST SET 3: Complex Scenarios"
echo "═══════════════════════════════════════════════════════"
echo ""

run_test \
    "Complex code analysis - full module" \
    "general-prompt" \
    "$(cat <<'EOF'
Perform a comprehensive code review of this API Gateway implementation,
identifying bugs, security issues, performance problems, and design improvements:

// API Gateway with rate limiting and circuit breaker
class APIGateway {
    constructor(config) {
        this.routes = new Map();
        this.rateLimit = new RateLimiter(config.rateLimit);
        this.circuitBreaker = new CircuitBreaker(config.circuitBreaker);
        this.metrics = new MetricsCollector();
    }

    registerRoute(path, handler, options = {}) {
        this.routes.set(path, {
            handler,
            auth: options.auth || false,
            rateLimit: options.rateLimit || 100,
            timeout: options.timeout || 30000
        });
    }

    async handleRequest(req, res) {
        const route = this.routes.get(req.path);
        if (!route) {
            return this.notFound(res);
        }

        // Rate limiting check
        if (!await this.rateLimit.check(req.ip, route.rateLimit)) {
            return this.rateExceeded(res);
        }

        // Circuit breaker check
        if (!this.circuitBreaker.isAvailable(req.path)) {
            return this.serviceUnavailable(res);
        }

        try {
            const result = await Promise.race([
                route.handler(req),
                this.timeout(route.timeout)
            ]);

            this.circuitBreaker.recordSuccess(req.path);
            this.metrics.recordSuccess(req.path);
            return this.send(res, result);
        } catch (error) {
            this.circuitBreaker.recordFailure(req.path);
            this.metrics.recordError(req.path, error);
            return this.error(res, error);
        }
    }

    timeout(ms) {
        return new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Timeout')), ms)
        );
    }
}
EOF
)"

run_test \
    "Complex plan review" \
    "plan-review" \
    "$(cat <<'EOF'
# Implementation Plan: Multi-tenant SaaS Authentication System

## Phase 1: Database Schema
1. Create tenants table with isolation strategy
2. Create users table with tenant_id foreign key
3. Add indexes for performance (tenant_id, email combinations)
4. Implement row-level security policies

## Phase 2: Authentication Service
1. Implement tenant identification from subdomain/header
2. Create JWT token generation with tenant context
3. Add password hashing with bcrypt (cost factor 12)
4. Implement refresh token rotation
5. Add rate limiting per tenant (100 req/min)

## Phase 3: Authorization
1. Create roles and permissions tables
2. Implement RBAC with tenant isolation
3. Add middleware for permission checking
4. Create admin endpoints for role management

## Phase 4: Security
1. Add CSRF protection
2. Implement session management
3. Add audit logging for authentication events
4. Set up monitoring and alerting

## Phase 5: Testing
1. Unit tests for auth logic
2. Integration tests for all endpoints
3. Load testing (1000 concurrent users per tenant)
4. Security testing (OWASP Top 10)
EOF
)"

echo ""
echo "════════════════════════════════════════════════════════"
echo "ANALYSIS"
echo "════════════════════════════════════════════════════════"
echo ""

# Generate statistics from CSV
if command -v bc &> /dev/null; then
    total_tests=$(tail -n +2 timing-results.csv | wc -l)
    successful=$(tail -n +2 timing-results.csv | grep -c "SUCCESS" || echo "0")
    failed=$(tail -n +2 timing-results.csv | grep -c "FAILED" || echo "0")
    timeouts=$(tail -n +2 timing-results.csv | grep -c ",YES" || echo "0")

    # Calculate duration statistics
    durations=$(tail -n +2 timing-results.csv | cut -d',' -f3)

    min_duration=$(echo "$durations" | sort -n | head -1)
    max_duration=$(echo "$durations" | sort -n | tail -1)

    # Calculate average
    sum=$(echo "$durations" | paste -sd+ | bc)
    avg_duration=$(echo "scale=2; $sum / $total_tests" | bc)

    # Calculate median
    median=$(echo "$durations" | sort -n | awk '{arr[NR]=$1} END {if (NR%2==1) print arr[(NR+1)/2]; else print (arr[NR/2]+arr[NR/2+1])/2}')

    echo "Total tests: $total_tests"
    echo "Successful: $successful"
    echo "Failed: $failed"
    echo "Timeouts (30s): $timeouts"
    echo ""
    echo "Duration Statistics:"
    echo "  Min: ${min_duration}s"
    echo "  Max: ${max_duration}s"
    echo "  Avg: ${avg_duration}s"
    echo "  Median: ${median}s"
    echo ""

    # Check if any tests exceeded 30 seconds
    exceeded_30=$(echo "$durations" | awk '$1 > 30' | wc -l)
    exceeded_45=$(echo "$durations" | awk '$1 > 45' | wc -l)
    exceeded_60=$(echo "$durations" | awk '$1 > 60' | wc -l)

    echo "Tests exceeding timeout thresholds:"
    echo "  > 30s (current): $exceeded_30"
    echo "  > 45s: $exceeded_45"
    echo "  > 60s: $exceeded_60"
    echo ""

    # Recommendation
    echo "💡 Recommendation:"
    if [ "$exceeded_30" -gt 0 ]; then
        echo "   ⚠️  Current 30s timeout is TOO SHORT"
        echo "   ${exceeded_30} out of ${total_tests} tests exceeded 30 seconds"

        if [ "$exceeded_45" -eq 0 ]; then
            echo "   Recommended timeout: 45-50 seconds"
        elif [ "$exceeded_60" -eq 0 ]; then
            echo "   Recommended timeout: 60-75 seconds"
        else
            echo "   Recommended timeout: 90+ seconds"
        fi
    else
        echo "   ✓ Current 30s timeout appears adequate"
        echo "   Consider adding 10-15s buffer for network variability"
        echo "   Recommended timeout: 40-45 seconds"
    fi
fi

echo ""
echo "Full results saved to: timing-results.csv"
