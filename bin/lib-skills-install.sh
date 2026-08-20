#!/usr/bin/env bash
# lib-skills-install.sh — installazione delle skill nelle directory dei tool.
#
# Sourced by bin/sync.sh (--install). Vive fuori da sync.sh per la stessa ragione per cui il
# motore delle suite vive in test/lib-suites.sh: sync.sh era gia' oltre le 300 righe, e la
# baseline dice che un file oltre soglia si SPEZZA, non si allarga. Usa `list`, `fm` e `P`
# definiti da sync.sh: non e' eseguibile da solo, e non deve esserlo.
#
# Testato da test/test-skill-name-collision.sh (collisioni di nome) e da
# test/test-sync-install.sh (symlink, skip, idempotenza).

# Skills → symlink install (defensive: never overwrite, never delete). For each
# generated wrapper platforms/claude/skills/<name>/SKILL.md, if <target>/<name>/
# does not exist yet, create it and symlink SKILL.md to the repo's generated wrapper — so
# it stays in sync automatically whenever the canon changes (no static copy to drift).
# If <target>/<name>/ already exists (e.g. a same-named skill from another skill
# system such as gstack), SKIP it explicitly rather than silently overriding it.
# Generalized over a list of (label, target dir) pairs — the same
# source wrapper set (SKILL.md is a portable format) is symlinked into
# every detected tool's skills dir, instead of duplicating the loop per tool.
#
# DIRECTORY name is not identity. Claude and Copilot both resolve a skill by the
# `name:` in its frontmatter, so a directory check alone misses the real collision:
# gstack ships `gstack-review/` declaring `name: review`, the directory is free, we
# install our `review/` next to it, and the host then keeps exactly ONE skill called
# `review` — ours loses, silently, with no warning anywhere. Detect the collision on
# the DECLARED name and install ours under `rdos-<name>` instead, so neither system
# disappears and both stay invocable (`/review` = theirs, `/rdos-review` = ours).
NS_PREFIX="rdos-"
NS_MARKER="<!-- roberdan-os: namespaced install (skill-name collision) -->"

# Directory of any FOREIGN skill under $1 declaring name $2, ignoring the two dirs
# that are legitimately ours ($3 plain, $4 namespaced). Empty + rc 1 when none.
#
# `find -L`, not the shared `list` helper: gstack installs its skills into ~/.claude/skills
# and then SYMLINKS the directories into ~/.copilot/skills. A plain find never descends into
# a symlinked directory, so the scan came back empty exactly where the collision was real —
# on the Copilot side — and both copies got installed again. -L follows the link; the sort
# keeps the pick deterministic when more than one foreign skill declares the same name.
foreign_owner_of_name() {
  local dir="$1" want="$2" mine_plain="$3" mine_ns="$4" f owner
  [ -n "$want" ] || return 1
  for f in $(find -L "$dir" -maxdepth 2 -name "SKILL.md" -type f 2>/dev/null | LC_ALL=C sort); do
    owner="$(dirname "$f")"
    [ "$owner" = "$mine_plain" ] && continue
    [ "$owner" = "$mine_ns" ] && continue
    if [ "$(fm "$f" name)" = "$want" ]; then echo "$owner"; return 0; fi
  done
  return 1
}

# True only when <dir>/SKILL.md is an install WE made: a symlink into the generated
# wrapper tree, or a namespaced wrapper carrying our marker. Anything else is another
# system's skill and is never touched — this predicate is what makes the retire/heal
# branches below safe to delete from.
install_is_ours() {
  local f="$1/SKILL.md" ps_abs="$2" rp
  if [ -L "$f" ]; then
    rp="$(cd "$(dirname "$(readlink "$f")")" 2>/dev/null && pwd)" || return 1
    case "$rp/" in "$ps_abs"/*) return 0 ;; esac
    return 1
  fi
  [ -f "$f" ] && grep -qF "$NS_MARKER" "$f" 2>/dev/null && return 0
  return 1
}

# Namespaced wrapper: the generated wrapper with its frontmatter `name:` rewritten and
# our marker appended. A symlink cannot carry a different name, and the wrapper body is
# already a thin pointer to skills/<name>/skill.md, so nothing drifts — the canon is
# still read from the repo at run time. Echoes INSTALL / SKIP so the run stays idempotent.
write_ns_wrapper() {
  local src="$1" target="$2" nsname="$3" canon="$4" tmpf
  mkdir -p "$target"
  tmpf="$target/.SKILL.md.new"
  {
    awk -v ns="$nsname" '
      BEGIN { fmc = 0; renamed = 0 }
      /^---$/ { fmc++ }
      (fmc == 1 && renamed == 0 && $1 == "name:") { print "name: " ns; renamed = 1; next }
      { print }
    ' "$src"
    echo ""
    echo "$NS_MARKER"
    echo "Installed as \`$nsname\` because another skill system on this machine already"
    echo "declares the name \`$canon\`. Same canon, different invocation name."
  } > "$tmpf"
  if [ -f "$target/SKILL.md" ] && cmp -s "$tmpf" "$target/SKILL.md"; then
    rm -f "$tmpf"
    echo "SKIP $canon: già installato come $nsname (collisione di nome)"
  else
    mv "$tmpf" "$target/SKILL.md"
    echo "INSTALL $canon: come $nsname in $target/SKILL.md (nome '$canon' già occupato)"
  fi
}

install_skills_set() {
  local label="$1" target_dir="$2"
  echo ""
  echo "--- skills install ($label, symlink, into $target_dir) ---"
  mkdir -p "$target_dir"
  local w sname declared plain ns clash ps_abs
  ps_abs="$(cd "$P/claude/skills" 2>/dev/null && pwd)" || ps_abs="$P/claude/skills"
  for w in $(list "$P/claude/skills" "SKILL.md" 2); do
    sname="$(basename "$(dirname "$w")")"
    declared="$(fm "$w" name)"; [ -n "$declared" ] || declared="$sname"
    plain="$target_dir/$sname"
    ns="$target_dir/$NS_PREFIX$sname"
    clash="$(foreign_owner_of_name "$target_dir" "$declared" "$plain" "$ns" || true)"

    if [ -n "$clash" ]; then
      if [ -e "$ns" ] && ! install_is_ours "$ns" "$ps_abs"; then
        echo "SKIP $sname: $ns/ già presente e non è nostro (mai overwrite)"
        continue
      fi
      write_ns_wrapper "$w" "$ns" "$NS_PREFIX$declared" "$declared"
      # Retire our own shadowed copy: it can never load while $clash owns the name.
      if [ -d "$plain" ] && install_is_ours "$plain" "$ps_abs"; then
        rm -f "$plain/SKILL.md"
        rmdir "$plain" 2>/dev/null || true
        echo "  rimosso $plain/ — era oscurato da $(basename "$clash")/ (stesso name: $declared)"
      elif [ -e "$plain" ]; then
        echo "  lasciato $plain/ intatto — non è nostro"
      fi
      continue
    fi

    # No collision. Heal a namespaced install left over from a system since removed,
    # so exactly one copy of each canon skill exists at any time.
    if [ -d "$ns" ] && install_is_ours "$ns" "$ps_abs"; then
      rm -f "$ns/SKILL.md"
      rmdir "$ns" 2>/dev/null || true
      echo "HEAL $sname: collisione sparita, rimosso $ns/ (torna a $sname)"
    fi

    if [ -e "$plain" ]; then
      echo "SKIP $sname: già presente in $plain/ (verifica manualmente se è una collisione con un altro sistema di skill, es. gstack)"
      continue
    fi
    mkdir -p "$plain"
    ln -s "$w" "$plain/SKILL.md"
    echo "INSTALL $sname: symlink $plain/SKILL.md -> $w"
  done
}

