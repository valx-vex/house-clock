#!/usr/bin/env bash
# Tests for hooks/clock.sh.   Run:  bash tests/run.sh
# Needs bash and python3 (python3 only reads the JSON the hook prints).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLOCK="$ROOT/hooks/clock.sh"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/home"
pass=0; fail=0

# 2026-11-19 05:23:00 UTC, a Thursday.
NOW=1795065780

ok() { pass=$((pass+1)); printf 'ok    %s\n' "$1"; }
ko() { fail=$((fail+1)); printf 'FAIL  %s\n      got: %s\n' "$1" "$2"; }

# hook <stdin> [VAR=value ...]  -> the raw output of the hook, in a clean environment
hook() {
  local in="$1"; shift
  printf '%s' "$in" | env -i PATH="$PATH" HOME="$T/home" TZ=UTC LC_ALL=C \
    HOUSE_CLOCK_STATE_DIR="$T/state" HOUSE_CLOCK_NOW="$NOW" "$@" "${BASH_UNDER_TEST:-bash}" "$CLOCK"
}
# line <stdin> [VAR=value ...]  -> the context line, read back out of the JSON
line() {
  hook "$@" | python3 -c 'import json,sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "UserPromptSubmit", d
print(d["additionalContext"])'
}
is()       { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "$2"; fi; }
has()      { case "$2" in *"$3"*) ok "$1";; *) ko "$1" "$2";; esac; }
has_not()  { case "$2" in *"$3"*) ko "$1" "$2";; *) ok "$1";; esac; }

sid() { printf '{"session_id":"%s","transcript_path":"/x/y.jsonl","cwd":"/x","hook_event_name":"UserPromptSubmit","prompt":"hello"}' "$1"; }

# --- the base line -----------------------------------------------------------
is "the day, the date, the time, the zone" \
   "$(line "$(sid a1)")" "[house clock] Thursday 2026-11-19 05:23 UTC"

hook "$(sid a1b)" >/dev/null; is "exit code is 0" "$?" "0"

is "no gap on the first message of a conversation" \
   "$(line "$(sid first)")" "[house clock] Thursday 2026-11-19 05:23 UTC"

# --- the gap since the previous message --------------------------------------
gap() { # gap <seconds> -> the line of a second message sent <seconds> after the first
  local s="g$1"
  hook "$(sid "$s")" >/dev/null
  line "$(sid "$s")" HOUSE_CLOCK_NOW=$((NOW + $1))
}
has_not "under a minute: nothing"      "$(gap 59)"      "previous message"
has "one minute"                       "$(gap 60)"      "· previous message 1 min ago"
has "ten minutes"                      "$(gap 600)"     "· previous message 10 min ago"
has "59 minutes"                       "$(gap 3599)"    "· previous message 59 min ago"
has "one hour sharp"                   "$(gap 3600)"    "· previous message 1 h ago"
has "nine hours forty-two"             "$(gap 34920)"   "· previous message 9 h 42 min ago"
has "one day"                          "$(gap 86400)"   "· previous message 1 day ago"
has "three days two hours"             "$(gap 266400)"  "· previous message 3 days 2 h ago"
has "a clock that went backwards: nothing, no crash" "$(gap -500)" "[house clock] "
has_not "a clock that went backwards: no gap"        "$(gap -500)" "previous message"

hook "$(sid one)" >/dev/null
has_not "two conversations do not share a gap" \
   "$(line "$(sid two)" HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"

has_not "HOUSE_CLOCK_SHOW=none: no gap" \
   "$(hook "$(sid n1)" HOUSE_CLOCK_SHOW=none >/dev/null; line "$(sid n1)" HOUSE_CLOCK_SHOW=none HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"

# --- input that is hostile, broken or missing --------------------------------
before="$(find "$T" -type f | sort)"
hook '{"session_id":"../../../escape","prompt":"x"}' >/dev/null
hook '{"session_id":"../../../escape","prompt":"x"}' >/dev/null
esc="$(find "$T" -type f | sort | grep -v "^$T/state/" || true)"
is "a session id with ../ writes nothing outside the state folder" "$esc" ""
[ -e "$T/escape" ] || [ -e "$T/../escape" ] && ko "no file named escape" "exists" || ok "no file named escape"

has "empty stdin still gives the date"   "$(line '')"            "Thursday 2026-11-19 05:23 UTC"
has "garbage stdin still gives the date" "$(line 'not json {{{')" "Thursday 2026-11-19 05:23 UTC"
has "no session id: the date, no gap"    "$(line '{"prompt":"x"}')" "Thursday 2026-11-19 05:23 UTC"

quoted='{"session_id":"q1","prompt":"he said \"session_id\": \"zzz\" and left"}'
hook "$quoted" >/dev/null
has "a prompt that quotes session_id does not change the conversation" \
   "$(line "$quoted" HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message 10 min ago"
[ -e "$T/state/zzz.last" ] && ko "no state file for the quoted id" "zzz.last exists" || ok "no state file for the quoted id"

mkdir -p "$T/ro"; chmod 500 "$T/ro"
has "a state folder that cannot be written: the date, exit 0" \
   "$(line "$(sid ro1)" HOUSE_CLOCK_STATE_DIR="$T/ro/deeper")" "Thursday 2026-11-19 05:23 UTC"

# --- options -----------------------------------------------------------------
is "a custom label" \
   "$(line "$(sid l1)" HOUSE_CLOCK_LABEL='the watch')" "[the watch] Thursday 2026-11-19 05:23 UTC"
is "a custom format" \
   "$(line "$(sid f1)" HOUSE_CLOCK_FORMAT='%H:%M')" "[house clock] 05:23"
is "a format with a quote and a backslash stays valid JSON" \
   "$(line "$(sid f2)" HOUSE_CLOCK_FORMAT='%H"%M\ok')" '[house clock] 05"23\ok'
is "a label with a quote stays valid JSON" \
   "$(line "$(sid l2)" HOUSE_CLOCK_LABEL='a "b"')" '[a "b"] Thursday 2026-11-19 05:23 UTC'

d="$(line "$(sid d1)" HOUSE_CLOCK_SHOW=disk)"
if printf '%s' "$d" | grep -Eq '· disk [0-9]+ GB free$'; then ok "disk: free space in GB"; else ko "disk: free space in GB" "$d"; fi

b="$(line "$(sid b1)" HOUSE_CLOCK_SHOW=battery)"
if printf '%s' "$b" | grep -Eq '^\[house clock\] Thursday 2026-11-19 05:23 UTC( · battery [0-9]+%(, on battery)?)?$'; then
  ok "battery: a percentage, or nothing on a machine without one"; else ko "battery" "$b"; fi

all="$(hook "$(sid all)" HOUSE_CLOCK_SHOW='gap, battery ,disk' >/dev/null; line "$(sid all)" HOUSE_CLOCK_SHOW='gap, battery ,disk' HOUSE_CLOCK_NOW=$((NOW + 600)))"
has "several options, with spaces around the commas" "$all" "· previous message 10 min ago"
has "several options: disk is there too"             "$all" "GB free"
has "an unknown option is ignored" "$(line "$(sid u1)" HOUSE_CLOCK_SHOW='moon,gap')" "Thursday 2026-11-19 05:23 UTC"

# --- the same options, set through the plugin's own settings ------------------
# Claude Code hands a plugin's options to its hooks as CLAUDE_PLUGIN_OPTION_<KEY>.
is "plugin option: label" \
   "$(line "$(sid p1)" CLAUDE_PLUGIN_OPTION_LABEL='watch')" "[watch] Thursday 2026-11-19 05:23 UTC"
is "plugin option: format" \
   "$(line "$(sid p2)" CLAUDE_PLUGIN_OPTION_FORMAT='%H:%M')" "[house clock] 05:23"
has "plugin option: show" \
   "$(line "$(sid p3)" CLAUDE_PLUGIN_OPTION_SHOW='disk')" "GB free"
has_not "plugin option: show=none turns the gap off" \
   "$(hook "$(sid p4)" CLAUDE_PLUGIN_OPTION_SHOW=none >/dev/null; line "$(sid p4)" CLAUDE_PLUGIN_OPTION_SHOW=none HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"
is "an environment variable wins over the plugin option" \
   "$(line "$(sid p5)" CLAUDE_PLUGIN_OPTION_LABEL='watch' HOUSE_CLOCK_LABEL='mine')" "[mine] Thursday 2026-11-19 05:23 UTC"
is "an empty plugin option falls back to the default" \
   "$(line "$(sid p6)" CLAUDE_PLUGIN_OPTION_LABEL='' CLAUDE_PLUGIN_OPTION_FORMAT='' CLAUDE_PLUGIN_OPTION_SHOW='')" "[house clock] Thursday 2026-11-19 05:23 UTC"

# --- the real clock ----------------------------------------------------------
real="$(printf '%s' "$(sid real)" | env -i PATH="$PATH" HOME="$T/home" HOUSE_CLOCK_STATE_DIR="$T/state" "${BASH_UNDER_TEST:-bash}" "$CLOCK" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
has "without HOUSE_CLOCK_NOW it reads the real clock" "$real" "$(date +%Y-%m-%d)"

# --- old state is swept ------------------------------------------------------
touch -t 202001010000 "$T/state/ancient.last"; : > "$T/state/keep.txt"; touch -t 202001010000 "$T/state/keep.txt"
hook "$(sid sweep)" >/dev/null
[ -e "$T/state/ancient.last" ] && ko "a state file older than 30 days is removed" "still there" || ok "a state file older than 30 days is removed"
[ -e "$T/state/keep.txt" ] && ok "a file that is not ours is left alone" || ko "a file that is not ours is left alone" "removed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
