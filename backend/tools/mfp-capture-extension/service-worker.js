chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'FOOD_APP_MFP_SAVE') return false;
  saveCapture(message.payload)
    .then((result) => sendResponse({ ok: true, result }))
    .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
  return true;
});

async function saveCapture(payload) {
  const { pending, capture } = payload || {};
  if (!pending?.caseId || !pending?.apiBase || !pending?.internalKey) {
    throw new Error('Missing Food App benchmark case context. Start from Lookup MFP in the dashboard.');
  }
  const response = await fetch(`${pending.apiBase}/v1/internal/dashboard/accuracy-benchmarks/cases/${pending.caseId}/mfp`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-internal-metrics-key': pending.internalKey
    },
    body: JSON.stringify(capture)
  });
  if (!response.ok) {
    throw new Error(`Food App save failed: HTTP ${response.status}`);
  }
  await chrome.storage.local.remove('foodAppMfpPending');
  return response.json();
}
