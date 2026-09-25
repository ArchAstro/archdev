#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [repository-root]\n' "${0##*/}" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  repo="$(cd -P "$1" && pwd)"
else
  repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ ! -d "$repo/skills" ]]; then
  printf 'No skills found under %s/skills.\n' "$repo"
  exit 0
fi

skill_files=()
while IFS= read -r -d '' skill_file; do
  skill_files+=("$skill_file")
done < <(find "$repo/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)

if [[ ${#skill_files[@]} -eq 0 ]]; then
  printf 'No skills found under %s/skills.\n' "$repo"
  exit 0
fi

for skill_file in "${skill_files[@]}"; do
  skill_name="$(basename "$(dirname "$skill_file")")"
  test_file="$repo/tests/$skill_name-skill.sh"
  if [[ ! -f "$test_file" ]]; then
    printf 'Skill %s is missing its acceptance test: tests/%s-skill.sh\n' \
      "$skill_name" "$skill_name" >&2
    exit 1
  fi
  if [[ ! -x "$test_file" ]]; then
    printf 'Skill acceptance test is not executable: tests/%s-skill.sh\n' \
      "$skill_name" >&2
    exit 1
  fi
  printf 'Running %s skill acceptance test...\n' "$skill_name"
  "$test_file"
done
