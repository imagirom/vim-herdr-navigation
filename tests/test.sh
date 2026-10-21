#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export HERDR_BIN_PATH="$repo/tests/mock-herdr.sh"
export HERDR_NAV_TEST_LOG="$tmp/herdr.log"
export HERDR_PANE_ID=w-test:p1
# Pin the opt-in off for the cases below: with HERDR_NAV_SPILL exported (as the
# README suggests) and the mock answering `pane focus`, they would otherwise
# take the spill path. The spill cases set it themselves.
export HERDR_NAV_SPILL=

assert_command() {
  local expected=$1
  local actual
  actual=$(tail -n 1 "$HERDR_NAV_TEST_LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'expected command: %s\nactual command:   %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

assert_no_stderr() {
  if [ -s "$1" ]; then
    printf 'expected nothing on stderr, got:\n%s\n' "$(cat "$1")" >&2
    exit 1
  fi
}

# Every herdr call the run made, one per line -- for the cases that are about
# what was *not* called.
assert_log() {
  local expected=$1
  local actual
  actual=$(cat "$HERDR_NAV_TEST_LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'expected log:\n%s\nactual log:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

export HERDR_NAV_TEST_PROCESS=nvim
"$repo/navigate.sh" left
assert_command 'pane send-keys w-test:p1 ctrl+h'

export HERDR_NAV_TEST_PROCESS=zsh
"$repo/navigate.sh" down
assert_command 'pane focus --direction down --pane w-test:p1'

export HERDR_NAV_TEST_PROCESS=lazygit
export HERDR_NAV_PASSTHROUGH_RE='^lazygit$'
"$repo/navigate.sh" up
assert_command 'pane send-keys w-test:p1 ctrl+k'

export HERDR_NAV_PASSTHROUGH_RE='['
"$repo/navigate.sh" right
assert_command 'pane focus --direction right --pane w-test:p1'

unset HERDR_PANE_ID HERDR_NAV_PASSTHROUGH_RE
"$repo/navigate.sh" right
assert_command 'pane focus --direction right --current'

if "$repo/navigate.sh" sideways >/dev/null 2>&1; then
  printf 'unknown direction unexpectedly succeeded\n' >&2
  exit 1
fi

# Stale HERDR_BIN_PATH (e.g. the server binary was replaced by `herdr update`
# without a server restart, leaving ".../herdr (deleted)"): fall back to `herdr`
# on PATH.
rm -f "$HERDR_NAV_TEST_LOG"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HERDR_NAV_TEST_LOG"
EOF
chmod +x "$tmp/bin/herdr"
HERDR_PANE_ID=w-test:p1 HERDR_BIN_PATH="$tmp/nonexistent-herdr" PATH="$tmp/bin:$PATH" \
  "$repo/navigate.sh" right
assert_command 'pane focus --direction right --pane w-test:p1'

# Stale HERDR_BIN_PATH and nothing usable on PATH: fail loudly instead of
# silently doing nothing.
# Run bash by absolute path: with PATH emptied, the env shebang would fail first.
if HERDR_PANE_ID=w-test:p1 HERDR_BIN_PATH="$tmp/nonexistent-herdr" PATH="$tmp/empty" \
    "$BASH" "$repo/navigate.sh" right >/dev/null 2>"$tmp/stderr"; then
  printf 'stale binary with no PATH fallback unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'no usable herdr binary' "$tmp/stderr"

rm -f "$HERDR_NAV_TEST_LOG"
export HERDR_NAV_TEST_REPO="$repo"
export HERDR_PANE_ID=w-test:p1
env -u TMUX nvim --clean --headless -u NONE -l "$repo/tests/nvim.lua"

rm -f "$HERDR_NAV_TEST_LOG"
env -u TMUX nvim --clean --headless -u NONE -S "$repo/tests/vim.vim"
printf 'Vimscript navigation verification passed\n'

# --- edge spillover (HERDR_NAV_SPILL=1) ------------------------------------
export HERDR_NAV_TEST_PROCESS=zsh

# Opt-in: with HERDR_NAV_SPILL unset the pane stops dead at the edge even though
# the mock reports one and offers tabs to spill into -- the process-info probe
# and one `pane focus`, and no tab traffic at all.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2' HERDR_NAV_TEST_TAB=t1 \
  "$repo/navigate.sh" right >/dev/null
assert_log 'pane process-info --pane w-test:p1
pane focus --direction right --pane w-test:p1'

# A normal move: spill on but the pane is not at an edge. Exactly the same two
# calls as the spill-off case above -- no tab/workspace traffic.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=true \
  "$repo/navigate.sh" down
assert_log 'pane process-info --pane w-test:p1
pane focus --direction down --pane w-test:p1'

# An ordinary step, no wrap: right from the first of three tabs lands on the
# second, then walks leftwards into it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2 t3' HERDR_NAV_TEST_TAB=t1 \
  "$repo/navigate.sh" right
grep -Fqx 'tab focus t2' "$HERDR_NAV_TEST_LOG"
assert_command 'pane focus --direction left --current'

# Wrapping at the high end: right from the last of three tabs lands on the
# first, then walks leftwards into it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2 t3' HERDR_NAV_TEST_TAB=t3 \
  "$repo/navigate.sh" right
grep -Fqx 'tab focus t1' "$HERDR_NAV_TEST_LOG"
assert_command 'pane focus --direction left --current'

# Wrapping at the low end: up from the first of three workspaces lands on the
# last, then walks downwards into it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_WORKSPACES='w-a w-b w-c' HERDR_NAV_TEST_WS=w-a \
  "$repo/navigate.sh" up
grep -Fqx 'workspace focus w-c' "$HERDR_NAV_TEST_LOG"
assert_command 'pane focus --direction down --current'

# The other two directions, so each of the four (scope, step, land) triples in
# navigate.sh's case statement is covered: with only right and up exercised, a
# left or down that stepped the wrong way would pass. Three containers, not two
# -- modulo 2 the two step directions are indistinguishable.
#
# Wrapping at the low end of the tabs: left from the first of three lands on the
# last, then walks rightwards into it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2 t3' HERDR_NAV_TEST_TAB=t1 \
  "$repo/navigate.sh" left
grep -Fqx 'tab focus t3' "$HERDR_NAV_TEST_LOG"
assert_command 'pane focus --direction right --current'

# Wrapping at the high end of the workspaces: down from the last of three lands
# on the first, then walks upwards into it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_WORKSPACES='w-a w-b w-c' HERDR_NAV_TEST_WS=w-c \
  "$repo/navigate.sh" down
grep -Fqx 'workspace focus w-a' "$HERDR_NAV_TEST_LOG"
assert_command 'pane focus --direction up --current'

# A failed herdr call must report a failure, not exit 0 as if there had been
# nowhere to go -- and herdr's own error text must survive to stderr. One
# injection per call the tab path makes, in the order it makes them: the edge
# probe, the list, the tab focus, and the walk.
for call in 'pane focus --direction right' 'tab list' 'tab focus' \
            'pane focus --direction left'; do
  rm -f "$HERDR_NAV_TEST_LOG"
  if HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
      HERDR_NAV_TEST_TABS='t1 t2' HERDR_NAV_TEST_TAB=t1 HERDR_NAV_TEST_FAIL="$call" \
      "$repo/navigate.sh" right >/dev/null 2>"$tmp/spill-stderr"; then
    printf 'a failed herdr %s unexpectedly succeeded\n' "$call" >&2
    exit 1
  fi
  grep -q "navigate.sh: herdr $call failed" "$tmp/spill-stderr"
  grep -q mock_failure "$tmp/spill-stderr"
done

# The fifth call, `workspace list`, is only reached on the vertical path.
rm -f "$HERDR_NAV_TEST_LOG"
if HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
    HERDR_NAV_TEST_WORKSPACES='w-a w-b' HERDR_NAV_TEST_WS=w-a \
    HERDR_NAV_TEST_FAIL='workspace list' \
    "$repo/navigate.sh" up >/dev/null 2>"$tmp/spill-stderr"; then
  printf 'a failed herdr workspace list unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'navigate.sh: herdr workspace list failed' "$tmp/spill-stderr"
grep -q mock_failure "$tmp/spill-stderr"

# A reply we cannot parse: tolerated for the `changed` probe, because that call
# happens on every keypress and a herdr schema change must not start erroring
# per key -- jq's own complaint is swallowed with it.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2' HERDR_NAV_TEST_TAB=t1 \
  HERDR_NAV_TEST_GARBLE='pane focus' \
  "$repo/navigate.sh" right 2>"$tmp/spill-stderr"
assert_log 'pane process-info --pane w-test:p1
pane focus --direction right --pane w-test:p1'
assert_no_stderr "$tmp/spill-stderr"

# The walk's reply gets the same tolerance as the probe's: an unparseable one
# just ends the walk, where it already landed.
rm -f "$HERDR_NAV_TEST_LOG"
HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
  HERDR_NAV_TEST_TABS='t1 t2' HERDR_NAV_TEST_TAB=t1 \
  HERDR_NAV_TEST_GARBLE='--direction left' \
  "$repo/navigate.sh" right 2>"$tmp/spill-stderr"
assert_command 'pane focus --direction left --current'
assert_no_stderr "$tmp/spill-stderr"

# Not tolerated for a list call: there is no "nowhere to go" fallback when we
# cannot tell where we would have gone.
rm -f "$HERDR_NAV_TEST_LOG"
if HERDR_PANE_ID=w-test:p1 HERDR_NAV_SPILL=1 HERDR_NAV_TEST_FOCUS_CHANGED=false \
    HERDR_NAV_TEST_TABS='t1 t2' HERDR_NAV_TEST_TAB=t1 \
    HERDR_NAV_TEST_GARBLE='tab list' \
    "$repo/navigate.sh" right >/dev/null 2>"$tmp/spill-stderr"; then
  printf 'an unreadable tab list reply unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'navigate.sh: unreadable reply to herdr tab list' "$tmp/spill-stderr"

printf 'Edge spillover verification passed\n'

printf 'Herdr navigation verification passed\n'
