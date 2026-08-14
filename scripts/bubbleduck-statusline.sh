#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# BubbleDuck — bridge Claude Code's status-line payload into a file the app polls.
#
# Claude Code hands its status-line command a JSON blob on stdin that includes,
# for subscription accounts, the real server-side rate limits:
#
#   "rate_limits": {
#     "five_hour": {"used_percentage": 42.1, "resets_at": 1786690000},
#     "seven_day": {"used_percentage": 61.0, "resets_at": 1787200000}
#   }
#
# This script extracts that, writes it atomically to ~/.claude/bubbleduck-usage.json,
# and then hands the *unmodified* input to whatever status-line command you were
# already using, passed as arguments.
#
# Install by pointing statusLine.command at this script with your real command
# appended, e.g. in ~/.claude/settings.json:
#
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/bubbleduck-statusline.sh npx -y ccstatusline@latest"
#   }
#
# Notes and limits:
#   - Claude Code only emits rate_limits in INTERACTIVE sessions, for
#     subscription accounts, after the first API response. Headless `claude -p`
#     runs never populate it.
#   - The numbers are account-wide and server-side; they include usage from
#     claude.ai and from your other machines. What they do NOT do is update
#     while no interactive session is running here — BubbleDuck treats a
#     reading older than its staleness window as last-known, not live.
#   - Requires jq. Without it, the pass-through still works and BubbleDuck
#     simply never sees usage data.

set -u

OUT="${BUBBLEDUCK_USAGE_FILE:-$HOME/.claude/bubbleduck-usage.json}"

input=$(cat)

if command -v jq >/dev/null 2>&1; then
    # `select` keeps us from clobbering a good reading with nulls on the
    # renders where Claude Code hasn't populated rate_limits yet.
    data=$(printf '%s' "$input" | jq -c '
        select(.rate_limits != null)
        | {updated_at: (now | floor),
           five_hour: .rate_limits.five_hour,
           seven_day: .rate_limits.seven_day}
    ' 2>/dev/null)

    if [ -n "$data" ]; then
        tmp="${OUT}.tmp.$$"
        if printf '%s\n' "$data" > "$tmp" 2>/dev/null; then
            mv -f "$tmp" "$OUT" 2>/dev/null || rm -f "$tmp"
        else
            rm -f "$tmp"
        fi
    fi
fi

# Delegate to the wrapped status-line command, feeding it the original stdin.
# With no arguments this script is a silent tee and prints nothing.
if [ "$#" -gt 0 ]; then
    printf '%s' "$input" | "$@"
fi
