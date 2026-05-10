# Food App MFP Capture Extension

Internal Chrome extension for assisted MyFitnessPal competitor capture.

## Install locally

1. Open `chrome://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select this folder: `backend/tools/mfp-capture-extension`.
5. If you update files in this folder, click the extension reload button in `chrome://extensions`.

## Capture workflow

1. Open the Food App testing dashboard and unlock it with the internal metrics key.
2. Go to `Benchmarks`.
3. Click `Lookup MFP` for a benchmark case.
4. MyFitnessPal opens in a new tab with the food search text.
5. Choose the MFP food result that is the fairest consumer comparison.
6. Click the floating `Capture for Food App` button.
7. Review/edit calories, protein, carbs, fat, serving, and notes.
8. Click `Use this MFP result`.
9. Refresh the benchmark dashboard if needed.

## If the capture button does not appear

- Confirm the extension is enabled in `chrome://extensions`.
- Confirm you started from the dashboard `Lookup MFP` button.
- Reload the MyFitnessPal tab.
- Click `Clear pending` if the wrong benchmark case is shown, then start again from the dashboard.
- Pending capture context expires after 30 minutes.

## If values are missing or wrong

- Calories are required before save.
- Edit any field manually in the review modal before clicking `Use this MFP result`.
- Add a note if the selected MyFitnessPal entry is ambiguous, duplicated, or manually adjusted.

## Notes

- The extension does not know your MyFitnessPal password.
- It uses your existing logged-in browser session.
- It stores the dashboard internal key only in Chrome extension local storage after you click `Lookup MFP`.
- The stored pending capture is cleared after save, when you click `Clear pending`, or when it expires.
- It captures visible page content and asks for manual review before saving.
- It updates only the MFP comparison fields on the benchmark case; reference truth remains unchanged.
