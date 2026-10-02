#!/usr/bin/env bash
# Sourced by validate.sh: kb board resolution and its gate wiring stay together.

section "kb board selection fails closed"
if _suite test-kb-board-resolution; then _kb_resolution_rc=0; else _kb_resolution_rc=$?; fi
if _suite test-kb-board-hostile; then _kb_hostile_rc=0; else _kb_hostile_rc=$?; fi
if [ "$_kb_resolution_rc" -eq 0 ] && [ "$_kb_hostile_rc" -eq 0 ]; then
  ok "registered worktrees resolve correctly and hostile unknown repositories cannot mutate fallback"
else
  _suite_out test-kb-board-resolution
  _suite_out test-kb-board-hostile
  err "kb board resolution safety — see bash test/test-kb-board-resolution.sh and test/test-kb-board-hostile.sh"
fi
unset _kb_resolution_rc _kb_hostile_rc

if _suite test-worktree-registry; then
  ok "il registro delle copie di lavoro resta coerente"
else
  _suite_out test-worktree-registry
  err "test-worktree-registry"
fi

if _suite test-validate-wiring; then
  ok "ogni suite lanciata contribuisce davvero al verdetto"
else
  _suite_out test-validate-wiring
  err "test-validate-wiring"
fi
