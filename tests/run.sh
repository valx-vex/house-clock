#!/usr/bin/env bash
# Tests for hooks/clock.sh.   Run:  bash tests/run.sh
# Needs bash and python3 (python3 only reads the JSON the hook prints).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLOCK="$ROOT/hooks/clock.sh"
SH="$(command -v "${BASH_UNDER_TEST:-bash}")"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
# The state folder sits four levels down: a file that a broken script writes "three folders up"
# still lands inside $T, where the tests can see it.
ST="$T/a/b/c/state"
mkdir -p "$T/home" "$ST"
pass=0; fail=0

# 2026-11-19 05:23:00 UTC, a Thursday.
NOW=1795065780

ok() { pass=$((pass+1)); printf 'ok    %s\n' "$1"; }
ko() { fail=$((fail+1)); printf 'FAIL  %s\n      got: %s\n' "$1" "$2"; }

# hook <stdin> [VAR=value ...]  -> the raw output of the hook, in a clean environment
hook() {
  local in="$1"; shift
  printf '%s' "$in" | env -i PATH="$PATH" HOME="$T/home" TZ=UTC LC_ALL=C \
    HOUSE_CLOCK_STATE_DIR="$ST" HOUSE_CLOCK_NOW="$NOW" "$@" "$SH" "$CLOCK"
}
# strict: the bytes must be valid UTF-8, and the JSON must have exactly the expected keys
read_line() {
  python3 -c '
import json, sys
raw = sys.stdin.buffer.read()
d = json.loads(raw.decode("utf-8"))
h = d["hookSpecificOutput"]
assert sorted(h) == ["additionalContext", "hookEventName"], h
assert h["hookEventName"] == "UserPromptSubmit", h
sys.stdout.buffer.write(h["additionalContext"].encode("utf-8"))' 2>/dev/null || printf 'NO-VALID-OUTPUT'
}
# line <stdin> [VAR=value ...]  -> the context line, read back out of the JSON
line() { hook "$@" | read_line; }
is()       { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "$2"; fi; }
has()      { case "$2" in *"$3"*) ok "$1";; *) ko "$1" "$2";; esac; }
# has_not passes only on a real line that lacks the words: no output at all is a failure
has_not()  { case "$2" in '' | NO-VALID-OUTPUT) ko "$1" "no valid output";; *"$3"*) ko "$1" "$2";; *) ok "$1";; esac; }
there()    { if [ -e "$2" ]; then ok "$1"; else ko "$1" "missing: $2"; fi; }
gone()     { if [ -e "$2" ] || [ -L "$2" ]; then ko "$1" "still there: $2"; else ok "$1"; fi; }

# msg <session id> [prompt]  -> what Claude Code hands the hook
msg() { printf '{"session_id":"%s","transcript_path":"/x/y.jsonl","cwd":"/x","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" "${2-hello}"; }

# --- the base line -----------------------------------------------------------
is "the day, the date, the time, the zone" \
   "$(line "$(msg a1)")" "[house clock] Thursday 2026-11-19 05:23 UTC"

hook "$(msg a1b)" >/dev/null; is "exit code is 0" "$?" "0"

is "no gap on the first message of a conversation" \
   "$(line "$(msg first)")" "[house clock] Thursday 2026-11-19 05:23 UTC"

# --- the gap since the previous message --------------------------------------
gap() { # gap <seconds> -> the line of a second, different message sent <seconds> after the first
  local s="g$1"
  hook "$(msg "$s" "the first message")" >/dev/null
  line "$(msg "$s" "a second message, with other words, and a \\\"quote\\\"")" HOUSE_CLOCK_NOW=$((NOW + $1))
}
has_not "under a minute: nothing"      "$(gap 59)"      "previous message"
has "one minute"                       "$(gap 60)"      "· previous message 1 min ago"
has "ten minutes"                      "$(gap 600)"     "· previous message 10 min ago"
has "59 minutes"                       "$(gap 3599)"    "· previous message 59 min ago"
has "one hour sharp"                   "$(gap 3600)"    "· previous message 1 h ago"
has "nine hours forty-two"             "$(gap 34920)"   "· previous message 9 h 42 min ago"
has "one day"                          "$(gap 86400)"   "· previous message 1 day ago"
has "three days two hours"             "$(gap 266400)"  "· previous message 3 days 2 h ago"
has_not "a clock that went backwards: no gap, no crash" "$(gap -500)" "previous message"
has_not "more than ten years: not a gap, a broken file"  "$(gap 400000000)" "previous message"

hook "$(msg one)" >/dev/null
has_not "two conversations do not share a gap" \
   "$(line "$(msg two)" HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"

has_not "HOUSE_CLOCK_SHOW=none: no gap" \
   "$(hook "$(msg n1)" HOUSE_CLOCK_SHOW=none >/dev/null; line "$(msg n1)" HOUSE_CLOCK_SHOW=none HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"

# --- a timestamp file that is not what the hook wrote --------------------------
broken() { # broken <name> <content> -> the line of a message arriving 10 minutes after NOW
  printf '%s' "$2" > "$ST/hc-$1.last"
  line "$(msg "$1")" HOUSE_CLOCK_NOW=$((NOW + 600))
}
has_not "a file holding 0: no gap"                 "$(broken k0 '0')"               "previous message"
has_not "a file holding 08: no gap"                "$(broken k1 '08')"              "previous message"
has_not "a file holding a negative number: no gap" "$(broken k2 "-$NOW")"           "previous message"
has_not "a file holding letters and digits: no gap" "$(broken k3 '1a2b3c4d5e')"     "previous message"
has_not "a file holding forty digits: no gap"      "$(broken k4 '0000000000000000000000000000000000000007')" "previous message"
has_not "an empty file: no gap"                    "$(broken k5 '')"                "previous message"
has     "a file holding a real timestamp: the gap" "$(broken k6 "$NOW")"            "previous message 10 min ago"

# --- input that is hostile, broken or missing --------------------------------
hook '{"session_id":"../../../escape","prompt":"x"}' >/dev/null
hook '{"session_id":"../../../escape","prompt":"x"}' >/dev/null
is "a session id with ../ writes nothing outside the state folder" \
   "$(find "$T" \( -type f -o -type l \) ! -path "$ST/*" | sort)" ""
is "nothing named escape anywhere outside the state folder" \
   "$(find "$T" -name '*escape*' ! -path "$ST/*" | sort)" ""
there "the same message, cleaned, has its file inside the state folder" "$ST/hc-escape.last"

has "empty stdin still gives the date"   "$(line '')"            "Thursday 2026-11-19 05:23 UTC"
has "garbage stdin still gives the date" "$(line 'not json {{{')" "Thursday 2026-11-19 05:23 UTC"
has "no session id: the date, no gap"    "$(line '{"prompt":"x"}')" "Thursday 2026-11-19 05:23 UTC"

quoted='{"session_id":"q1","prompt":"he said \"session_id\": \"zzz\" and left"}'
hook "$quoted" >/dev/null
has "a prompt that quotes session_id does not change the conversation" \
   "$(line "$quoted" HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message 10 min ago"
gone "no state file for the quoted id" "$ST/hc-zzz.last"

hook '{"session_id":"main","prompt":"x","agent":{"session_id":"sub"}}' >/dev/null
there "with two session_id keys, the first one is the conversation" "$ST/hc-main.last"
gone  "with two session_id keys, the second one is not"             "$ST/hc-sub.last"

# 2 MB of message: the hook reads all of it (the writer must not get a broken pipe), and still answers
{ printf '{"session_id":"big","prompt":"'; head -c 2000000 /dev/zero | tr '\0' 'a'; printf '"}'; } |
  env -i PATH="$PATH" HOME="$T/home" TZ=UTC LC_ALL=C HOUSE_CLOCK_STATE_DIR="$ST" HOUSE_CLOCK_NOW="$NOW" "$SH" "$CLOCK" > "$T/big.out"
wr=${PIPESTATUS[0]}
is "a 2 MB message: the writer is not cut off" "$wr" "0"
has "a 2 MB message: the line is there" "$(read_line < "$T/big.out")" "Thursday 2026-11-19 05:23 UTC"
rm -f "$T/big.out"

mkdir -p "$T/ro"; chmod 500 "$T/ro"
has "a state folder that cannot be written: the date, exit 0" \
   "$(line "$(msg ro1)" HOUSE_CLOCK_STATE_DIR="$T/ro/deeper")" "Thursday 2026-11-19 05:23 UTC"

# a link sitting where the timestamp file goes: the hook replaces the link, it never writes through it
printf 'precious' > "$T/victim.txt"; ln -s "$T/victim.txt" "$ST/hc-lnk.last"
hook "$(msg lnk)" >/dev/null
is "a link at the file's name: what it points to is left alone" "$(cat "$T/victim.txt")" "precious"
if [ -L "$ST/hc-lnk.last" ]; then ko "a link at the file's name is replaced by a real file" "still a link"; else ok "a link at the file's name is replaced by a real file"; fi
rm -f "$T/victim.txt"

# no HOME and no folder given: nowhere private to write, so no file at all (never a shared /tmp)
out="$(printf '%s' "$(msg nohome)" | env -i PATH="$PATH" TZ=UTC LC_ALL=C HOUSE_CLOCK_NOW="$NOW" "$SH" "$CLOCK" | read_line)"
has "no HOME, no state folder: the date all the same" "$out" "Thursday 2026-11-19 05:23 UTC"
gone "no HOME, no state folder: nothing written under /tmp" "/tmp/.local/state/house-clock/hc-nohome.last"

# --- options -----------------------------------------------------------------
is "a custom label" \
   "$(line "$(msg l1)" HOUSE_CLOCK_LABEL='the watch')" "[the watch] Thursday 2026-11-19 05:23 UTC"
is "a custom format" \
   "$(line "$(msg f1)" HOUSE_CLOCK_FORMAT='%H:%M')" "[house clock] 05:23"
is "a format with a quote and a backslash stays valid JSON" \
   "$(line "$(msg f2)" HOUSE_CLOCK_FORMAT='%H"%M\ok')" '[house clock] 05"23\ok'
is "a label with a quote stays valid JSON" \
   "$(line "$(msg l2)" HOUSE_CLOCK_LABEL='a "b"')" '[a "b"] Thursday 2026-11-19 05:23 UTC'
long="$(line "$(msg f3)" HOUSE_CLOCK_FORMAT="$(printf 'x%.0s' $(seq 1 3000))")"
if [ "$long" != NO-VALID-OUTPUT ] && [ ${#long} -lt 400 ]; then ok "a 3000-character format: valid, and cut short"; else ko "a 3000-character format: valid, and cut short" "${#long} characters"; fi

d="$(line "$(msg d1)" HOUSE_CLOCK_SHOW=disk)"
if printf '%s' "$d" | grep -Eq '· disk [0-9]+ GB free$'; then ok "disk: free space in GB"; else ko "disk: free space in GB" "$d"; fi

b="$(line "$(msg b1)" HOUSE_CLOCK_SHOW=battery)"
if printf '%s' "$b" | grep -Eq '^\[house clock\] Thursday 2026-11-19 05:23 UTC( · battery [0-9]+%(, on battery)?)?$'; then
  ok "battery: a percentage, or nothing on a machine without one"; else ko "battery" "$b"; fi

all="$(hook "$(msg all)" HOUSE_CLOCK_SHOW='gap, battery ,disk' >/dev/null; line "$(msg all)" HOUSE_CLOCK_SHOW='gap, battery ,disk' HOUSE_CLOCK_NOW=$((NOW + 600)))"
has "several options, with spaces around the commas" "$all" "· previous message 10 min ago"
has "several options: disk is there too"             "$all" "GB free"
has "an unknown option is ignored" "$(line "$(msg u1)" HOUSE_CLOCK_SHOW='moon,gap')" "Thursday 2026-11-19 05:23 UTC"

# --- the same options, set through the plugin's own settings ------------------
# Claude Code hands a plugin's options to its hooks as CLAUDE_PLUGIN_OPTION_<KEY>.
is "plugin option: label" \
   "$(line "$(msg p1)" CLAUDE_PLUGIN_OPTION_LABEL='watch')" "[watch] Thursday 2026-11-19 05:23 UTC"
is "plugin option: format" \
   "$(line "$(msg p2)" CLAUDE_PLUGIN_OPTION_FORMAT='%H:%M')" "[house clock] 05:23"
has "plugin option: show" \
   "$(line "$(msg p3)" CLAUDE_PLUGIN_OPTION_SHOW='disk')" "GB free"
has_not "plugin option: show=none turns the gap off" \
   "$(hook "$(msg p4)" CLAUDE_PLUGIN_OPTION_SHOW=none >/dev/null; line "$(msg p4)" CLAUDE_PLUGIN_OPTION_SHOW=none HOUSE_CLOCK_NOW=$((NOW + 600)))" "previous message"
is "an environment variable wins over the plugin option" \
   "$(line "$(msg p5)" CLAUDE_PLUGIN_OPTION_LABEL='watch' HOUSE_CLOCK_LABEL='mine')" "[mine] Thursday 2026-11-19 05:23 UTC"
is "an empty plugin option falls back to the default" \
   "$(line "$(msg p6)" CLAUDE_PLUGIN_OPTION_LABEL='' CLAUDE_PLUGIN_OPTION_FORMAT='' CLAUDE_PLUGIN_OPTION_SHOW='')" "[house clock] Thursday 2026-11-19 05:23 UTC"

# --- a machine whose dates are not written in UTF-8 ---------------------------
# (on a machine without these locales, the day name is in English and the checks still hold)
nolc() { printf '%s' "$(msg "$1")" | env -i PATH="$PATH" HOME="$T/home" TZ=UTC HOUSE_CLOCK_STATE_DIR="$ST" HOUSE_CLOCK_NOW="$NOW" "${@:2}" "$SH" "$CLOCK" | read_line; }
has "text in UTF-8, dates in ISO-8859: the date and the time are still there" \
   "$(nolc lc1 LANG=en_US.UTF-8 LC_TIME=it_IT.ISO8859-1)" "2026-11-19 05:23 UTC"
has "everything in ISO-8859: valid UTF-8 comes out, with the date" \
   "$(nolc lc2 LC_ALL=it_IT.ISO8859-1)" "2026-11-19 05:23 UTC"
has "everything in ISO-8859-2, with the disk: nothing is lost" \
   "$(nolc lc3 LANG=en_US.UTF-8 LC_TIME=sk_SK.ISO8859-2 HOUSE_CLOCK_SHOW=disk)" "GB free"

# --- the real clock ----------------------------------------------------------
real="$(printf '%s' "$(msg real)" | env -i PATH="$PATH" HOME="$T/home" HOUSE_CLOCK_STATE_DIR="$ST" "$SH" "$CLOCK" | read_line)"
has "without HOUSE_CLOCK_NOW it reads the real clock" "$real" "$(date +%Y-%m-%d)"

# no date command at all: say nothing, rather than hand over a watch with no hands
out="$(printf '%s' "$(msg nodate)" | env -i PATH="$T/nowhere" HOME="$T/home" HOUSE_CLOCK_STATE_DIR="$ST" "$SH" "$CLOCK" 2>/dev/null; echo "exit=$?")"
is "no date command: no output, exit 0" "$out" "exit=0"

# --- old state is swept, and only ours ---------------------------------------
old() { : > "$1"; touch -t 202001010000 "$1"; }
old "$ST/hc-ancient.last"; old "$ST/meeting.last"; old "$ST/keep.txt"
hook "$(msg sweep)" >/dev/null
gone  "a timestamp file of ours, silent for years, is removed" "$ST/hc-ancient.last"
there "an old .last file that is not ours is left alone"       "$ST/meeting.last"
there "any other old file is left alone"                       "$ST/keep.txt"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
