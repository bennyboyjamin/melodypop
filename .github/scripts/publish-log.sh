#!/bin/bash
# Pushes a CI failure log to a throwaway branch (ci-logs/<run>-<name>) so it can be read with git.
set -u
name="$1"; file="$2"
[ -f "$file" ] || exit 0
branch="ci-logs/${GITHUB_RUN_ID}-${name}"
tmp=$(mktemp -d)
grep -E "error:|warning: .*\.swift|Test Case.*failed|XCTAssert|: failed|\*\* (BUILD|TEST)" "$file" | head -400 > "$tmp/summary.txt" || true
tail -400 "$file" > "$tmp/tail.txt"
cd "$tmp"
git init -q
git config user.name "ci"
git config user.email "ci@users.noreply.github.com"
git add summary.txt tail.txt
git commit -qm "CI log ${GITHUB_RUN_ID} ${name}"
git push -q "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/${branch}" --force
