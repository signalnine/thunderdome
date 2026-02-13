#!/usr/bin/env bash
set -e

echo "Testing multi-review.sh..."

# Test: Missing arguments
if ./skills/requesting-code-review/multi-review.sh 2>&1 | grep -q "Usage:"; then
    echo "✓ Shows usage when no arguments"
else
    echo "✗ Should show usage when no arguments"
    exit 1
fi

# Test: Context preparation
# Create a test repo with commits
test_dir=$(mktemp -d)
cd "$test_dir"
git init -q
echo "line1" > file.txt
git add file.txt
git commit -q -m "first commit"
FIRST_SHA=$(git rev-parse HEAD)
echo "line2" >> file.txt
git commit -q -am "second commit"
SECOND_SHA=$(git rev-parse HEAD)

# Run script in dry-run mode (add --dry-run flag)
if $OLDPWD/skills/requesting-code-review/multi-review.sh \
    "$FIRST_SHA" "$SECOND_SHA" "-" "test change" --dry-run 2>&1 \
    | grep -q "Modified files: 1"; then
    echo "✓ Extracts git context correctly"
else
    echo "✗ Should extract git context"
    exit 1
fi

cd "$OLDPWD"

# Test: Empty diff (same commit)
cd "$test_dir"
SAME_SHA=$(git rev-parse HEAD)
if $OLDPWD/skills/requesting-code-review/multi-review.sh \
    "$SAME_SHA" "$SAME_SHA" "-" "no changes" --dry-run 2>&1 \
    | grep -q "Modified files: 0"; then
    echo "✓ Handles empty diff correctly"
else
    echo "✗ Should report 0 files for empty diff"
    exit 1
fi
cd "$OLDPWD"

rm -rf "$test_dir"

# Test: Issue similarity matching
echo "Testing consensus algorithm..."

# Source the functions (need to extract them for testing)
# Create a test script that sources the functions
cat > /tmp/test-consensus-functions.sh <<'TESTEOF'
#!/usr/bin/env bash
set -e

# Source the multi-review.sh functions
SIMILARITY_THRESHOLD="${SIMILARITY_THRESHOLD:-60}"

# Extract filename from issue description
extract_filename() {
    local description="$1"
    local filename=$(echo "$description" | grep -oE '\b[a-zA-Z0-9_/-]+\.(sh|py|js|ts|md|go|rs|java)\b' | head -1)
    if [ -n "$filename" ]; then
        filename=$(echo "$filename" | sed 's|^\./||')
        echo "$filename"
        return 0
    fi
    echo ""
}

# Calculate word overlap
word_overlap_percent() {
    local desc1="$1"
    local desc2="$2"
    if [ -z "$desc1" ] || [ -z "$desc2" ]; then
        echo "0"
        return
    fi
    local stop_words="the a an and or but in on at to for of with is are was were be been being have has had do does did will would should could may might must can"
    local words1=$(echo "$desc1" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)
    local words2=$(echo "$desc2" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)
    for stop in $stop_words; do
        words1=$(echo "$words1" | grep -v "^${stop}$" || true)
        words2=$(echo "$words2" | grep -v "^${stop}$" || true)
    done
    if [ -z "$words1" ] || [ -z "$words2" ]; then
        echo "0"
        return
    fi
    common=$(comm -12 <(echo "$words1") <(echo "$words2") | wc -l | tr -d ' ')
    total=$(echo "$words1" | wc -l | tr -d ' ')
    if [ "$total" -eq 0 ]; then
        echo "0"
        return
    fi
    echo "scale=0; ($common * 100) / $total" | bc
}

# Check if issues are similar
issues_similar() {
    local issue1="$1"
    local issue2="$2"
    local file1=$(extract_filename "$issue1")
    local file2=$(extract_filename "$issue2")
    if [ -n "$file1" ] && [ -n "$file2" ] && [ "$file1" != "$file2" ]; then
        return 1
    fi
    local overlap=$(word_overlap_percent "$issue1" "$issue2")
    if [ "$overlap" -ge "$SIMILARITY_THRESHOLD" ]; then
        return 0
    else
        return 1
    fi
}

# Run tests
test_filename_extraction() {
    # Test path normalization
    file1=$(extract_filename "Error in ./src/foo.js line 10")
    file2=$(extract_filename "Error in src/foo.js line 10")
    if [ "$file1" = "$file2" ] && [ "$file1" = "src/foo.js" ]; then
        echo "✓ Filename normalization works"
    else
        echo "✗ Filename normalization failed: '$file1' != '$file2'"
        exit 1
    fi
}

test_word_overlap() {
    # Test similar descriptions
    overlap=$(word_overlap_percent "missing error handling in main function" "no error handling in main function")
    if [ "$overlap" -ge 60 ]; then
        echo "✓ Word overlap detects similar issues ($overlap%)"
    else
        echo "✗ Word overlap too low for similar issues: $overlap%"
        exit 1
    fi

    # Test dissimilar descriptions
    overlap=$(word_overlap_percent "missing error handling" "add logging support")
    if [ "$overlap" -lt 60 ]; then
        echo "✓ Word overlap rejects dissimilar issues ($overlap%)"
    else
        echo "✗ Word overlap too high for dissimilar issues: $overlap%"
        exit 1
    fi
}

test_issue_similarity() {
    # Same file, similar content
    if issues_similar "Missing validation in src/foo.js" "No validation in src/foo.js"; then
        echo "✓ Similar issues in same file matched"
    else
        echo "✗ Should match similar issues in same file"
        exit 1
    fi

    # Different files
    if ! issues_similar "Missing validation in src/foo.js" "Missing validation in src/bar.js"; then
        echo "✓ Issues in different files not matched"
    else
        echo "✗ Should not match issues in different files"
        exit 1
    fi

    # Same file, different content
    if ! issues_similar "Missing input validation" "Need better documentation"; then
        echo "✓ Dissimilar issues not matched"
    else
        echo "✗ Should not match dissimilar issues"
        exit 1
    fi
}

test_filename_extraction
test_word_overlap
test_issue_similarity
TESTEOF

chmod +x /tmp/test-consensus-functions.sh
/tmp/test-consensus-functions.sh
rm -f /tmp/test-consensus-functions.sh

echo "All tests passed!"
