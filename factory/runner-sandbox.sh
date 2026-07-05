#!/usr/bin/env bash
# factory/runner-sandbox.sh — the credential-vacuum sandbox for the restricted
# external runner (design §Node 3a). SOURCED by dispatch-runner.sh and by the
# @thor acceptance tests; sets no shell options.
#
# The guarantee is capability ABSENCE, not a denylist. `env -i` starts EMPTY (an
# ALLOWLIST, @luca #8) and passes ONLY what a CLI legitimately needs — GH_TOKEN,
# GITHUB_TOKEN, GH_ENTERPRISE_TOKEN and SSH_AUTH_SOCK are simply never in it, so no
# `unset` can be forgotten. Every git the dispatcher runs is additionally forced
# credential-less + config-neutral: `-c credential.helper=` (empty) RESETS the
# helper list, which DEFEATS a hostile repo-local .git/config credential helper
# (osxkeychain etc.) that GIT_CONFIG_NOSYSTEM / GIT_CONFIG_GLOBAL alone do NOT
# disable. With no token in env, no reachable helper, and no ssh-agent socket, a
# push to ANY remote (origin, an injected SSH/https remote, one the runner adds
# itself) has nowhere to authenticate and fails — even via the real /usr/bin/git.

# sandbox_env_run <shim_bindir> <home> <tmpdir> [--] cmd [args...]
# Runs cmd under the env -i allowlist. The shim bindir is FIRST on PATH (first-line
# defense + audit); the credential vacuum is the actual guarantee, not the shims.
sandbox_env_run() {
  local bindir="$1" home="$2" tmpdir="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  env -i \
    PATH="$bindir:/usr/bin:/bin" \
    HOME="$home" \
    TERM="${TERM:-xterm}" \
    LANG="${LANG:-C}" \
    TMPDIR="$tmpdir" \
    "$@"
}

# sandbox_git <repo> <git-args...> — every git the dispatcher runs against the
# untrusted repo, forced credential-less + config-neutral.
sandbox_git() {
  local repo="$1"; shift
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -c credential.helper= -c protocol.version=2 -C "$repo" "$@"
}
