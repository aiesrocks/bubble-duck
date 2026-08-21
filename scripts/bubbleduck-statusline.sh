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
#   - Every interactive session writes this one file. Each reports the limits
#     that session last saw, so an idle one re-emits an hours-old snapshot on
#     every render. Writes are therefore guarded: a reading is only taken if it
#     opens a newer window or reports at least as much usage in the current one.
#   - Requires jq. Without it, the pass-through still works and BubbleDuck
#     simply never sees usage data.

set -u

OUT="${BUBBLEDUCK_USAGE_FILE:-$HOME/.claude/bubbleduck-usage.json}"

input=$(cat)

if command -v jq >/dev/null 2>&1; then
    # Every interactive session on this machine writes this same file, and each
    # one reports the rate_limits *it* last saw. An idle session keeps
    # re-rendering its status line every refreshInterval and re-emits a snapshot
    # that may be hours old, so a naive last-writer-wins clobbers a live reading
    # with a stale one — and because we stamp updated_at ourselves, the app's
    # staleness check can never catch it.
    #
    # Guard with the one invariant these numbers have: within a window,
    # used_percentage only climbs, and resets_at is fixed. So take the incoming
    # value only when it opens a newer window, or reports at least as much usage
    # in the current one. Anything older is a stale session and gets dropped.
    prev=$(jq -c '.' "$OUT" 2>/dev/null) || prev=""
    [ -n "$prev" ] || prev="null"

    data=$(printf '%s' "$input" | jq -c --argjson prev "$prev" '
        # true when $new should replace $old
        def fresher($new; $old):
            if $new == null then false
            elif $old == null then true
            elif ($new.resets_at // 0) > ($old.resets_at // 0) then true
            elif ($new.resets_at // 0) < ($old.resets_at // 0) then false
            else ($new.used_percentage // 0) >= ($old.used_percentage // 0)
            end;

        select(.rate_limits != null)
        | .rate_limits as $in
        | fresher($in.five_hour; $prev.five_hour) as $takeFive
        | fresher($in.seven_day; $prev.seven_day) as $takeSeven
        | select($takeFive or $takeSeven or $prev == null)
        | {updated_at: (if $takeFive or $takeSeven
                        then (now | floor)
                        else ($prev.updated_at // (now | floor)) end),
           five_hour: (if $takeFive then $in.five_hour else $prev.five_hour end),
           seven_day: (if $takeSeven then $in.seven_day else $prev.seven_day end)}
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
