# iOS Parse + Detail + Clarification + Save (FE-006, FE-007, FE-008, FE-009)

## What is implemented
- Notes-style text input on main logging screen.
- Debounced parse calls (`~550ms`) to `POST /v1/logs/parse`.
- Manual `Parse Now` trigger.
- Live response rendering:
  - totals (calories/protein/carbs/fat)
  - confidence
  - route/fallback signal
  - parsed items
  - assumptions
  - clarification questions when `needsClarification=true`
- Details drawer with editable parsed items:
  - editable name, quantity, and unit
  - totals update from edited values
  - contract-compatible save payload preview (`parseRequestId`, `parseVersion`, `parsedLog`)
- Strict save flow (`POST /v1/logs`) with idempotency safety:
  - save sends `parseRequestId`, `parseVersion`, and `Idempotency-Key`
  - same draft reuses the same key for safe retry/replay semantics
  - conflict/stale parse errors map to clear user-facing messages
- Clarification + escalation UX (`POST /v1/logs/parse/escalate`):
  - clarification questions are shown when `needsClarification=true`
  - escalation is an explicit user action via `Escalate Parse`
  - escalation-disabled and budget-exceeded states are shown with clear UI messaging

## Local validation steps
1. Start backend:
```bash
cd "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend"
npm run dev
```

2. Run app in Debug from Xcode.

3. Complete onboarding once (or use existing persisted state).

4. On main logging screen, type:
- `2 eggs, 2 slices toast, black coffee`

Expected:
- Parse auto-runs after brief typing pause.
- Totals and parsed items render.
- Confidence and route details render.
- "Open Details Drawer" is enabled after successful parse.

5. Type ambiguous text:
- `mystery bowl from cafe`

Expected:
- Clarification-needed state appears.
- Clarification questions render.
- Questions and assumptions appear inside Details Drawer.

6. Open Details Drawer and change one item quantity.

Expected:
- Item nutrition values scale with quantity edit.
- Summary totals on main screen update to reflect edited values.
- Save payload preview remains valid JSON.

7. Tap **Save Log**.

Expected:
- Save succeeds with a success message and returned `logId`.
- UI displays the current idempotency key for retry safety.

8. With the same draft unchanged, tap **Save Log** again (or **Retry Last Save**).

Expected:
- Request safely reuses the same idempotency key.
- Backend replays prior success without creating duplicate records.

9. Change note text, parse again, then save.

Expected:
- A new idempotency key is generated for this new intended save action.
- Save succeeds as a separate log action.

10. Test escalation with ambiguous text:
- `avocado sandwich`
- Tap **Parse Now**.
- Tap **Escalate Parse**.

Expected:
- Clarification questions appear first.
- Escalation runs only when you explicitly tap the button.
- On success, clarification state clears and save becomes available.
- If escalation is disabled or budget is exhausted, button/message explain why.

## Notes
- Save is disabled when parse response has `needsClarification=true`.
