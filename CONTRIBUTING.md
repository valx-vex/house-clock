# Contributing

The whole thing is one bash file of about 150 lines. Read it first.

## Bugs and ideas

Open an issue. Say what happened and what you expected.

## Code

Fork, branch, change, test (`bash tests/run.sh` — all 63 must pass), then
open a pull request. Keep it small: one fix, one feature, one PR.

## Tests

The test suite is strict on purpose. If you add behavior, add a test. If you
fix a bug, add a test that would have caught it. Run the full suite before
you push.

## Style

No dependencies. No network. No surprises. The hook must never block a
message, and must exit 0 no matter what.
