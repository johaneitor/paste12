## paste12 runbook (PR, deploy, verify, rollback)

- Prereqs:
  - Ensure environment variables if needed: `CAP_LIMIT` (default 400)
  - Optional: `RENDER_GIT_COMMIT` for `/api/deploy-stamp`

### Create PR and push

```bash
# from repo root
export PR_BRANCH="cursor/apply-fixes-p12"
git fetch origin
# if not already on branch created by Cursor, create it:
if ! git rev-parse --verify "$PR_BRANCH" >/dev/null 2>&1; then
  git checkout -b "$PR_BRANCH" origin/main
fi
# review changes and push
git push -u origin "$PR_BRANCH"
# create PR
gh pr create --title "[p12-fix] backend+frontend alignment; POST/view/report; limits; CORS; deploy-stamp" --body "Automated fixes and audit scripts." --base main --head "$PR_BRANCH"
```

### Deploy (Render)
- Option A: Deploy hook
```bash
curl -X POST "$RENDER_DEPLOY_HOOK"
```
- Option B: API
```bash
export RENDER_API_KEY=... RENDER_SERVICE_ID=...
render services deploy $RENDER_SERVICE_ID --wait
```

### Verify
```bash
OUTDIR="./p12-audit"
mkdir -p "$OUTDIR"
# static checks summary already in 01-static-checks.txt if run locally
./tools/patchless_audit_remote_deep_full_v1.sh "$BASE" "$OUTDIR"
cat "$OUTDIR/deploy-stamp.json"
```
- Confirm:
  - POST returns 201 and `{ok:true, id, item}`
  - View dedupe OK (second view with same `X-FP` does not increment)
  - Report removed only after 3 distinct `X-FP`
  - Legacy negatives return 404
  - Rate-limit present (429 when exceeded)
  - `/api/deploy-stamp` shows HEAD commit or env value
  - Index has `p12-commit`, `p12-safe-shim`, and `<body data-single="1">`

### Rollback
- Re-deploy previous successful commit on Render.
- Temporarily set higher limits or disable via env if needed:
  - `CAP_LIMIT` to adjust capacity
  - Rate-limiter storage to Redis for stability in multi-instance.
