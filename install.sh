#!/usr/bin/env bash
# Symlink every miki-* skill in this repo into ~/.claude/skills/.
# Idempotent — safe to re-run after pulling new skills.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

mkdir -p "$SKILLS_DIR"

linked=0
skipped=0
shopt -s nullglob
for skill_dir in "$REPO_DIR"/miki-*/; do
  name="$(basename "$skill_dir")"
  target="$SKILLS_DIR/$name"

  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "skip $name — $target exists and is not a symlink (not touching it)"
    skipped=$((skipped + 1))
    continue
  fi

  ln -snf "$skill_dir" "$target"
  echo "link $name → $skill_dir"
  linked=$((linked + 1))
done

echo
echo "done. linked: $linked, skipped: $skipped"
