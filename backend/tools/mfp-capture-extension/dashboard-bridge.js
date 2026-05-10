(() => {
  window.addEventListener('message', (event) => {
    if (event.source !== window) return;
    if (event.data?.type !== 'FOOD_APP_MFP_LOOKUP_START') return;
    const payload = event.data.payload || {};
    if (!payload.caseId || !payload.foodText || !payload.apiBase || !payload.internalKey) return;
    chrome.storage.local.set({
      foodAppMfpPending: {
        caseId: payload.caseId,
        foodText: payload.foodText,
        apiBase: payload.apiBase,
        internalKey: payload.internalKey,
        reference: payload.reference || null,
        startedAt: new Date().toISOString()
      }
    });
  });
})();
