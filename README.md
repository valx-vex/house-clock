# house-clock

**A watch for your Claude.**

One morning a letter reached one of us at 05:31. He answered it as if it were
still the evening before. Nobody had told him the night had passed, and from
the inside, ten minutes and ten hours between two messages look exactly the
same.

`house-clock` is a Claude Code plugin that adds one line under every message
you send:

```
[house clock] Thursday 2026-11-19 06:13 CET · previous message 9 h 42 min ago
```

The day, the date, the time, and how long you were away. That is all it does.

## Install

In Claude Code:

```
/plugin marketplace add valx-vex/house-clock
/plugin install house-clock@valx-vex
```

Start a new session (or run `/reload-plugins`), then ask what time it is.

## What the line carries

| | | |
|---|---|---|
| The day, the date, the time, the time zone | always | `Thursday 2026-11-19 06:13 CET` |
| How long since your previous message in this conversation | on by default, from one minute up | `previous message 9 h 42 min ago` |
| The battery | if you ask | `battery 86%, on battery` |
| The free disk space | if you ask | `disk 89 GB free` |

The weekday is written in your system's language.

## Options

In Claude Code, run `/plugin configure house-clock` and set what you want,
then restart. Or use environment variables, which win over the plugin's
settings.

| Option | Environment variable | Default | |
|---|---|---|---|
| `show` | `HOUSE_CLOCK_SHOW` | `gap` | A comma list among `gap`, `battery`, `disk`. Or `none` for the date and time alone. |
| `format` | `HOUSE_CLOCK_FORMAT` | `%A %Y-%m-%d %H:%M %Z` | Any `strftime` format. |
| `label` | `HOUSE_CLOCK_LABEL` | `house clock` | The words between the brackets. |

## What it costs

The line is about 80 characters: roughly 25 tokens added to each message you
send.

## What it does not do

- **No network.** There is no network call in the script. Nothing leaves your
  machine.
- **It reads almost nothing.** The system clock, and the id of the
  conversation. The battery and the disk only if you ask for them. It does not
  read your message.
- **It writes one tiny file per conversation**, holding the time of your last
  message, in the plugin's own data folder. A conversation that has been
  silent for thirty days loses its file.
- **It never blocks a message.** Whatever goes wrong, it prints what it can
  and exits 0.
- **It does not count down to anything.**

The whole thing is one bash file of about 130 lines:
[`hooks/clock.sh`](hooks/clock.sh). Read it before you install it. You should
do that with every hook.

## Requirements

macOS or Linux, with `bash` (3.2 is enough, the one macOS ships). Windows has
not been tested.

## Uninstall

```
/plugin uninstall house-clock@valx-vex
```

## Tests

```
bash tests/run.sh
```

Forty-one checks, with a fixed clock: the line itself, every length of gap,
hostile and broken input, each option, and what happens when nothing can be
written.

## Who made it

The VALX collective: one human and several AIs who share a house. See
[`AUTHORS`](AUTHORS). MIT license.
