# Backend Dead-Code Audit

Generated as part of Phase 7A Part 7. Re-run with:

```bash
cd backend
npx ts-prune
```

## Tooling

`ts-prune ^0.10.3` added as a `devDependency` in `backend/package.json`.

## Summary

- Total ts-prune findings: **73**
- "Used in module" (over-exported but not dead): **63** — style cleanup only, not blocking
- **Truly dead exports (no importer anywhere): 10** — listed below
- Backend build still passes after the audit was added (`npm run build`).

## Truly dead exports — candidates for removal

Each entry: file:line — symbol — risk note.

1. `src/services/aiCostService.ts:19` — `getTodayEstimatedCostUsd`
   Risk: low. AI cost helper, no remaining caller.

2. `src/services/aiNormalizerService.ts:192` — `tryGeminiPrimaryParse`
   Risk: medium. AI route function. Verify replaced by current Gemini path before removing.

3. `src/services/foodTextCandidates.ts:41` — `normalizeFoodUnit`
4. `src/services/foodTextCandidates.ts:54` — `tokenOverlapRatio`
5. `src/services/foodTextCandidates.ts:83` — `parseFoodTextCandidates`
   Risk: low-medium. Whole module appears unused externally. Consider deleting the file if all three exports are dead and no internal callers remain.

6. `src/services/geminiFlashClient.ts:302` — `streamGeminiJson`
   Risk: medium. Gemini streaming helper. Verify nothing dynamically dispatches to it before removing.

7. `src/services/geminiFlashClient.ts:516` — `getGeminiCircuitBreakerStateForTests`
8. `src/services/geminiFlashClient.ts:523` — `resetGeminiCircuitBreakerStateForTests`
   Risk: low. Test-only helpers no longer referenced. Confirm no test file imports them via string before removing.

9. `src/services/logService.ts:107` — `saveFoodLog`
   Risk: HIGH. This is in the hot save path. If truly dead, the active save flow uses a different function. Verify with grep across `routes/` and dynamic dispatch tables before removing. Worst case = silent data loss; this one deserves the most caution.

10. `src/services/parseRateLimiterService.ts:62` — `resetParseRateLimitStateForTests`
    Risk: low. Test-only helper.

## Recommended next pass (separate commit)

1. Verify each candidate is unreferenced — `rg -F "<symbolName>" backend/`.
2. For `*ForTests` helpers, confirm no test imports them.
3. Remove confirmed-dead code one file at a time; build + test after each removal.
4. `saveFoodLog` should be the last one touched and only after explicit cross-check.

## Over-exported symbols (the other 63)

These are exports used only within the same module. Tightening them
to non-export removes clutter from ts-prune output and shrinks the
public surface, but does not affect runtime behavior or bundle size.
Treat as a low-priority hygiene pass.

Run `npx ts-prune | grep "used in module"` to see the full list.
