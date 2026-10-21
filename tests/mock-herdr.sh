#!/usr/bin/env bash
set -euo pipefail

: "${HERDR_NAV_TEST_LOG:?HERDR_NAV_TEST_LOG must name the command log}"
printf '%s\n' "$*" >>"$HERDR_NAV_TEST_LOG"

# Make one chosen call fail: HERDR_NAV_TEST_FAIL is a substring of the argv.
# Checked before any reply is printed, so an injected failure never also prints
# a success body on stdout.
if [[ -n ${HERDR_NAV_TEST_FAIL:-} && $* == *"$HERDR_NAV_TEST_FAIL"* ]]; then
  printf '{"error":{"code":"mock_failure","message":"injected"},"id":"cli:mock"}\n' >&2
  exit 1
fi

# Make one chosen call reply with something jq cannot parse, exit 0 and all:
# HERDR_NAV_TEST_GARBLE is a substring of the argv, like HERDR_NAV_TEST_FAIL.
if [[ -n ${HERDR_NAV_TEST_GARBLE:-} && $* == *"$HERDR_NAV_TEST_GARBLE"* ]]; then
  printf 'not json at all\n'
  exit 0
fi

if [[ ${1:-} == pane && ${2:-} == process-info ]]; then
  printf '{"result":{"process_info":{"foreground_processes":[{"name":"%s"}]}}}\n' \
    "${HERDR_NAV_TEST_PROCESS:-zsh}"
fi

# `pane focus` replies only when HERDR_NAV_TEST_FOCUS_CHANGED is set, so the
# default path (which execs this mock) keeps printing nothing.
if [[ ${1:-} == pane && ${2:-} == focus && -n ${HERDR_NAV_TEST_FOCUS_CHANGED:-} ]]; then
  changed=$HERDR_NAV_TEST_FOCUS_CHANGED
  # --current here is the walk loop; the edge probe targets --pane. The walk
  # always stops after one step: no test needs a multi-step walk.
  [[ $* == *--current* ]] && changed=false
  printf '{"result":{"focus":{"changed":%s,"layout":{"workspace_id":"%s","tab_id":"%s"}}}}\n' \
    "$changed" "${HERDR_NAV_TEST_WS:-w-test}" "${HERDR_NAV_TEST_TAB:-t1}"
fi

if [[ ${1:-} == tab && ${2:-} == list && -n ${HERDR_NAV_TEST_TABS:-} ]]; then
  read -ra ids <<<"$HERDR_NAV_TEST_TABS"
  printf '{"result":{"tabs":['
  sep=
  for id in "${ids[@]}"; do
    printf '%s{"tab_id":"%s","workspace_id":"%s"}' "$sep" "$id" "${HERDR_NAV_TEST_WS:-w-test}"
    sep=,
  done
  printf ']}}\n'
fi

if [[ ${1:-} == workspace && ${2:-} == list && -n ${HERDR_NAV_TEST_WORKSPACES:-} ]]; then
  read -ra ids <<<"$HERDR_NAV_TEST_WORKSPACES"
  printf '{"result":{"workspaces":['
  sep=
  for id in "${ids[@]}"; do
    printf '%s{"workspace_id":"%s"}' "$sep" "$id"
    sep=,
  done
  printf ']}}\n'
fi
