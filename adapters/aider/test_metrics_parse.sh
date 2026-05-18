#!/bin/bash
# Regression test for aider adapter cost-regex parsing.
# Guards against the bash double-escape bug where a python3 -c "..." string
# eats backslashes and turns \$ into Python's end-of-string anchor.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/aider-output.txt" <<'EOF'
> aider message about something
Tokens: 1,234 sent, 567 received.
Cost: $0.0123 message, $0.0456 session.
EOF

metrics="$tmp/metrics.json"

# Mirror of the (fixed) parser block from adapter.sh, kept here for regression.
python3 - "$tmp/aider-output.txt" "$metrics" <<'PYEOF'
import json, re, sys
with open(sys.argv[1]) as f:
    text = f.read()
cost_re = re.compile(r'Cost:\s*\$([\d.]+)\s*message,\s*\$([\d.]+)\s*session', re.MULTILINE)
tok_re  = re.compile(r'Tokens:\s*([\d,]+)\s*sent,\s*([\d,]+)\s*received', re.MULTILINE)
session_cost = 0.0
inp, outp = 0, 0
for m in cost_re.finditer(text):
    session_cost = float(m.group(2))
for m in tok_re.finditer(text):
    inp  += int(m.group(1).replace(',', ''))
    outp += int(m.group(2).replace(',', ''))
with open(sys.argv[2], 'w') as f:
    json.dump({"input_tokens": inp, "output_tokens": outp, "total_cost_usd": session_cost}, f)
PYEOF

got=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["total_cost_usd"])' "$metrics")
expected="0.0456"
if [[ "$got" != "$expected" ]]; then
    echo "FAIL: total_cost_usd = $got, expected $expected" >&2
    exit 1
fi
echo "PASS: cost parsed correctly (total_cost_usd=$got)"
