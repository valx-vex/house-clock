# Changelog

## 0.1.1

What the adversarial review found, fixed before anyone installed it.

Three things worth fixing:

- The path-traversal test saw nothing: with the session-id filter removed,
  all checks stayed green. The test now looks everywhere outside the state
  folder.
- On a machine whose dates are not written in UTF-8, the line was cut at the
  first accent and the time was lost. The line is now filtered to valid
  UTF-8: an accent may go, the numbers stay.
- The monthly sweep removed every old `*.last` file of the state folder. The
  files are now named `hc-<id>.last`, and only those are swept.

And smaller ones: the timestamp file is written beside and renamed (a link
at that name is replaced, never written through); only a 9-to-11-digit
number is believed as a timestamp, and a gap of more than ten years is not
shown; the whole message is read; the first `session_id` of the input is the
conversation; with no private place to write, nothing is written (never a
shared `/tmp`); with no `date` command, nothing is printed; a format cannot
make the line endless; the disk is in decimal GB.

## 0.1.0

First release. The day, the date, the time, and how long you were away.
From "do it" to public, with 41 tests: 22 minutes.
