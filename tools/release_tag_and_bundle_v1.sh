#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-/sdcard/Download}"
mkdir -p "$OUTDIR"

sha="$(git rev-parse --short=12 HEAD)"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
tag="prod-${ts}-${sha}"

echo "== Tag =="
git tag -a "$tag" -m "paste12 release $tag"
git push --tags

echo "== Bundle artefactos =="
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -f tools/*.sh tools/*.py "$tmp/" 2>/dev/null || true
cp -f "$OUTDIR"/runtime-*.txt "$tmp/" 2>/dev/null || true
cp -f "$OUTDIR"/repo-audit-*.txt "$tmp/" 2>/dev/null || true
cp -f "$OUTDIR"/clones-*.txt "$tmp/" 2>/dev/null || true

tarball="$OUTDIR/paste12-release-${tag}.tar.gz"
tar -C "$tmp" -czf "$tarball" .
echo "Bundle: $tarball"
