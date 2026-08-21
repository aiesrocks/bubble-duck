#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Guard tests for bubbleduck-statusline.sh — multi-session stale-write rejection.
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bubbleduck-statusline.sh"
D=$(mktemp -d)
export BUBBLEDUCK_USAGE_FILE="$D/usage.json"
pass=0; fail=0

# payload builder: five_pct five_reset seven_pct seven_reset
pay() { printf '{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$3" "$4"; }

chk() { # name  expected_five  expected_seven
  local got_f got_s
  got_f=$(jq -r '.five_hour.used_percentage' "$BUBBLEDUCK_USAGE_FILE" 2>/dev/null)
  got_s=$(jq -r '.seven_day.used_percentage' "$BUBBLEDUCK_USAGE_FILE" 2>/dev/null)
  if [ "$got_f" = "$2" ] && [ "$got_s" = "$3" ]; then
    echo "  ok   $1  (5h=$got_f 7d=$got_s)"; pass=$((pass+1))
  else
    echo "  FAIL $1  expected 5h=$2 7d=$3, got 5h=$got_f 7d=$got_s"; fail=$((fail+1))
  fi
}

echo "1. cold start writes"
pay 62 2000 87 9000 | "$SCRIPT"
chk "accepts first reading" 62 87

echo "2. stale session (same window, lower pct) is dropped"
pay 29 2000 82 9000 | "$SCRIPT"
chk "keeps 62/87" 62 87

echo "3. genuine increase accepted"
pay 70 2000 88 9000 | "$SCRIPT"
chk "takes 70/88" 70 88

echo "4. new 5h window accepted even though pct drops"
pay 3 20000 89 9000 | "$SCRIPT"
chk "takes 3/89" 3 89

echo "5. stale session with the OLD window is dropped after reset"
pay 70 2000 88 9000 | "$SCRIPT"
chk "keeps 3/89" 3 89

echo "6. per-field: 5h stale, 7d fresh"
pay 1 20000 95 9000 | "$SCRIPT"
chk "keeps 5h=3, takes 7d=95" 3 95

echo "7. payload with no rate_limits leaves the file alone"
echo '{"model":{"id":"x"}}' | "$SCRIPT"
chk "unchanged" 3 95

echo "8. corrupt existing file recovers"
echo 'not json' > "$BUBBLEDUCK_USAGE_FILE"
pay 40 20000 50 30000 | "$SCRIPT"
chk "overwrites garbage" 40 50

echo "9. updated_at freshness"
before=$(jq -r .updated_at "$BUBBLEDUCK_USAGE_FILE")
sleep 1
pay 10 20000 20 30000 | "$SCRIPT"   # fully stale -> must not refresh updated_at
after=$(jq -r .updated_at "$BUBBLEDUCK_USAGE_FILE")
if [ "$before" = "$after" ]; then echo "  ok   stale write does not refresh updated_at"; pass=$((pass+1));
else echo "  FAIL updated_at moved $before -> $after on a stale write"; fail=$((fail+1)); fi

echo "10. stdin passes through to the wrapped command untouched"
p=$(pay 99 20000 99 30000)
out=$(printf '%s' "$p" | "$SCRIPT" cat)
if [ "$out" = "$p" ]; then echo "  ok   pass-through byte-identical"; pass=$((pass+1));
else echo "  FAIL pass-through differs"; fail=$((fail+1)); fi

echo "11. no-arg mode prints nothing"
out=$(pay 99 20000 99 30000 | "$SCRIPT")
if [ -z "$out" ]; then echo "  ok   silent tee"; pass=$((pass+1)); else echo "  FAIL printed: $out"; fail=$((fail+1)); fi

rm -rf "$D"
echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
