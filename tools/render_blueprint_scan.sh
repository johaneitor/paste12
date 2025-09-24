#!/usr/bin/env bash
set -euo pipefail
grep -RInE 'render\.ya?ml|start.?command|startCommand' -n . || true
