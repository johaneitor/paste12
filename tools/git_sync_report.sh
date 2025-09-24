#!/usr/bin/env bash
set -euo pipefail

echo "== REMOTES =="
git remote -v | sed -n '1,3p'
echo

echo "== STATUS (tracking) =="
git status -sb || true
echo

echo "== SHAs =="
HEAD_SHA=$(git rev-parse --short=12 HEAD)
ORI_SHA=$(git rev-parse --short=12 origin/main)
echo "HEAD        : $HEAD_SHA"
echo "origin/main : $ORI_SHA"
echo

echo "== AHEAD/BEHIND =="
git fetch -q origin main || true
git rev-list --left-right --count origin/main...HEAD | awk '{printf "behind=%s ahead=%s\n",$1,$2}'
echo

echo "== DIFF (working tree vs HEAD) =="
git diff --name-status || true
echo

echo "== DIFF (HEAD vs origin/main) =="
git diff --name-status origin/main...HEAD || true
echo

echo "== LAST 3 COMMITS (HEAD) =="
git log -n 3 --oneline
echo
echo "== LAST 3 COMMITS (origin/main) =="
git log -n 3 --oneline origin/main
