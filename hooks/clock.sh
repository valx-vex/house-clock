#!/usr/bin/env bash
# house-clock: a Claude Code hook (UserPromptSubmit).
#
# It adds one line under every message you send, so the model knows what day
# and what time it is, and how long it has been since your previous message:
#
#   [house clock] Thursday 2026-11-19 06:13 CET · previous message 9 h 42 min ago
#
# What it reads: the system clock; one small timestamp file per conversation;
# and, only if you ask for them, the battery level and the free disk space.
# What it sends anywhere: nothing. There is no network call in this file.
# It never blocks a message: whatever goes wrong, it prints what it can and
# exits 0.
#
# Options, all optional. Set them in the plugin's settings (/plugin, then
# house-clock), or as environment variables:
#   show    HOUSE_CLOCK_SHOW     comma list among gap, battery, disk; or "none".
#                                Default: gap
#   format  HOUSE_CLOCK_FORMAT   a strftime format.
#                                Default: %A %Y-%m-%d %H:%M %Z
#   label   HOUSE_CLOCK_LABEL    the words between the brackets.
#                                Default: house clock
#           HOUSE_CLOCK_STATE_DIR  where the timestamp files live.

set -u

# An environment variable wins; then the plugin's own option (Claude Code hands
# it over as CLAUDE_PLUGIN_OPTION_<KEY>); then the default.
opt_show="${HOUSE_CLOCK_SHOW:-${CLAUDE_PLUGIN_OPTION_SHOW:-}}"
opt_fmt="${HOUSE_CLOCK_FORMAT:-${CLAUDE_PLUGIN_OPTION_FORMAT:-}}"
opt_label="${HOUSE_CLOCK_LABEL:-${CLAUDE_PLUGIN_OPTION_LABEL:-}}"
show=",$(printf '%s' "${opt_show:-gap}" | tr -d '[:space:]'),"
fmt="${opt_fmt:-%A %Y-%m-%d %H:%M %Z}"
label="${opt_label:-house clock}"
state="${HOUSE_CLOCK_STATE_DIR:-${CLAUDE_PLUGIN_DATA:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/house-clock}}"

wants() { case "$show" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# --- now ---------------------------------------------------------------------
# HOUSE_CLOCK_NOW (seconds since 1970) fixes the instant. It exists for the tests.
now="${HOUSE_CLOCK_NOW:-}"
case "$now" in '' | *[!0-9]*) now="" ;; esac
if [ -n "$now" ]; then
  now=$((10#$now))
  if date --version >/dev/null 2>&1; then stamp=$(date -d "@$now" "+$fmt" 2>/dev/null)   # GNU date
  else stamp=$(date -r "$now" "+$fmt" 2>/dev/null); fi                                   # BSD date
else
  now=$(date +%s 2>/dev/null | tr -cd '0-9')
  stamp=$(date "+$fmt" 2>/dev/null)
fi
[ -n "${stamp:-}" ] || stamp=$(date 2>/dev/null)

# --- which conversation is this ----------------------------------------------
# Claude Code gives the hook a JSON object on stdin. The only field read here is
# session_id, and only letters, digits, _ and - are kept from it: it becomes a
# file name.
input=""
[ -t 0 ] || input=$(head -c 1048576 2>/dev/null | tr -d '\000')
sid=$(printf '%s' "$input" | tr '\n\r' '  ' |
  sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p' |
  tr -cd 'A-Za-z0-9_-' | cut -c1-80)

# --- how long since the previous message -------------------------------------
human() { # seconds -> "10 min", "9 h 42 min", "3 days 2 h"
  local s=$1 d h m out
  d=$((s / 86400)); h=$(((s % 86400) / 3600)); m=$(((s % 3600) / 60))
  if [ "$d" -gt 0 ]; then
    if [ "$d" -eq 1 ]; then out="1 day"; else out="$d days"; fi
    [ "$h" -gt 0 ] && out="$out $h h"
  elif [ "$h" -gt 0 ]; then
    out="$h h"; [ "$m" -gt 0 ] && out="$out $m min"
  else
    out="$m min"
  fi
  printf '%s' "$out"
}

gap=""
if wants gap && [ -n "$sid" ] && [ -n "$now" ]; then
  f="$state/$sid.last"
  if [ -f "$f" ]; then
    prev=$(head -c 16 "$f" 2>/dev/null | tr -cd '0-9')
    if [ -n "$prev" ]; then
      elapsed=$((now - 10#$prev))
      [ "$elapsed" -ge 60 ] && gap=$(human "$elapsed")
    fi
  fi
  if mkdir -p "$state" 2>/dev/null; then
    { printf '%s\n' "$now" >"$f"; } 2>/dev/null
    # conversations that have been silent for a month: their timestamp goes
    find "$state" -maxdepth 1 -type f -name '*.last' -mtime +30 -exec rm -f {} + 2>/dev/null
  fi
fi

# --- the machine, only if asked ----------------------------------------------
battery() {
  local raw pct="" on="" d
  if command -v pmset >/dev/null 2>&1; then # macOS
    raw=$(pmset -g batt 2>/dev/null)
    pct=$(printf '%s' "$raw" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    case "$raw" in *discharging*) on=1 ;; esac
  else # Linux
    for d in /sys/class/power_supply/BAT*; do
      [ -r "$d/capacity" ] || continue
      pct=$(tr -cd '0-9' <"$d/capacity" | cut -c1-3)
      case "$(cat "$d/status" 2>/dev/null)" in Discharging*) on=1 ;; esac
      break
    done
  fi
  [ -n "$pct" ] || return 0
  if [ -n "$on" ]; then printf 'battery %s%%, on battery' "$pct"; else printf 'battery %s%%' "$pct"; fi
}

disk() {
  local kb
  kb=$({ df -Pk "${HOME:-/}" 2>/dev/null || df -Pk / 2>/dev/null; } | awk 'NR==2 {print $4}' | tr -cd '0-9')
  [ -n "$kb" ] && printf 'disk %s GB free' "$((10#$kb / 1048576))"
}

# --- the line ----------------------------------------------------------------
line="[$label] $stamp"
[ -n "$gap" ] && line="$line · previous message $gap ago"
if wants battery; then b=$(battery); [ -n "$b" ] && line="$line · $b"; fi
if wants disk; then k=$(disk); [ -n "$k" ] && line="$line · $k"; fi

# JSON: no control characters, and \ and " escaped
esc=$(printf '%s' "$line" | tr '\n\r\t' '   ' | tr -d '\000-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$esc"
exit 0
