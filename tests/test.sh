#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export HERDR_BIN_PATH="$repo/tests/mock-herdr.sh"
export HERDR_NAV_TEST_LOG="$tmp/herdr.log"
export HERDR_PANE_ID=w-test:p1

assert_command() {
  local expected=$1
  local actual
  actual=$(tail -n 1 "$HERDR_NAV_TEST_LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'expected command: %s\nactual command:   %s\n' "$expected" "$actual" >&2
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

rm -f "$HERDR_NAV_TEST_LOG"
export HERDR_NAV_TEST_REPO="$repo"
export HERDR_PANE_ID=w-test:p1
env -u TMUX nvim --clean --headless -u NONE -l "$repo/tests/nvim.lua"

rm -f "$HERDR_NAV_TEST_LOG"
env -u TMUX nvim --clean --headless -u NONE -S "$repo/tests/vim.vim"
printf 'Vimscript navigation verification passed\n'

printf 'Herdr navigation verification passed\n'
