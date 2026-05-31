# End-to-End Code Review & Cleanup — PROGRESS / CHECKPOINT

**Branch:** `end-to-end-code-debug-and-review`
**Base (current main at start):** `e71e52d` — "Recipes: rebuild card grid + lock artwork size"
**Worktree (do ALL work here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-review-worktree`
**Main repo (NEVER touch — user's, Xcode open here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App`
**Separate DerivedData (keep out of git):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-derived-data`
**Started:** 2026-05-31, overnight autonomous run.

## STRICT RULES (user-mandated, non-negotiable)
- NEVER modify `main` (branch ref or working dir). No checkout/commit/push/merge into main. main stays at `e71e52d`.
- ALL edits/commits happen in THIS worktree on branch `end-to-end-code-debug-and-review`.
- If stuck, STAY stuck and document here. Do NOT fall back to main.
- Local only — no push, no PR until the user approves in the morning.
- Verify before claiming done: backend = `tsc --noEmit` + `vitest` green; iOS = `xcodebuild` green (separate DerivedData).
- Do NOT touch the parse/save/image save-path (see CLAUDE.md save-path rule) beyond clearly-dead code; no autonomous prod-DB end-to-end saves.
- Use `grep` not `rg` in Bash (shell `rg` is proxied/unreliable here). The Grep tool is fine.
- `RecipesViews.swift` was just rewritten on main (`e71e52d`) — user actively iterating; be conservative.

## VERIFICATION LOOP
- Backend: `node_modules` + `.env` are symlinked into the worktree from the main repo.
  - typecheck: `"<wt>/backend/node_modules/.bin/tsc" --noEmit -p "<wt>/backend/tsconfig.json"`
  - tests: `npm --prefix "<wt>/backend" test`  (vitest unit; integration is gated separately)
- iOS: `xcodebuild build -project "<wt>/Food App.xcodeproj" -scheme "Food App" -destination "generic/platform=iOS Simulator" -derivedDataPath "<dd>"`

## PHASES
- [x] 0. Worktree setup + main isolation verified
- [ ] 1. Baselines (backend tsc/vitest; iOS build green)
- [ ] 2. Exhaustive audit (read-only fan-out) — findings appended below
- [ ] 3. Adversarial verification of findings (kill false positives)
- [ ] 4. Apply safe cleanups (backend verified; iOS build-verified), isolated commits
- [ ] 5. Final report + morning summary

## BASELINES
- backend `tsc --noEmit`: PASS (0 errors) — confirmed pre-fast-forward; re-confirm in worktree
- backend `vitest`: PENDING
- iOS build: PENDING

## AUDIT FINDINGS (appended as agents report)
_pending — wave 1 dispatched: logging-shell, save/parse-core, auth/services, backend-services, backend-routes_

## COMMITS MADE ON BRANCH
_none yet (this PROGRESS.md will be the first)_

## HOW TO RESUME (after a usage-limit reset / fresh session)
1. Read this file top to bottom. Confirm the worktree still exists and `main` is still at `e71e52d` (untouched).
2. Re-read `CLAUDE.md` in the worktree for the save-path safety rule.
3. Continue from the first unchecked phase. Update checkboxes + findings as you go.
4. NEVER operate in the main repo dir. Stay in the worktree.
