(() => {
  const STATE_KEY = 'foodAppMfpPending';
  const MAX_PENDING_MS = 30 * 60 * 1000;

  hydratePendingFromHash();
  readPending((pending) => {
    if (!pending?.caseId) return;
    mountCaptureButton(pending);
  });

  function hydratePendingFromHash() {
    const marker = '#foodAppMfpCapture=';
    if (!location.hash.startsWith(marker)) return;
    try {
      const partial = JSON.parse(decodeURIComponent(location.hash.slice(marker.length)));
      if (!partial.caseId || !partial.foodText || !partial.apiBase) return;
      chrome.storage.local.get(STATE_KEY, (data) => {
        const existing = data[STATE_KEY] || {};
        chrome.storage.local.set({
          [STATE_KEY]: {
            ...existing,
            caseId: partial.caseId,
            foodText: partial.foodText,
            apiBase: partial.apiBase,
            reference: partial.reference || existing.reference || null,
            startedAt: existing.startedAt || new Date().toISOString()
          }
        });
      });
    } catch {
      // Ignore malformed hashes from unrelated pages.
    }
  }

  function readPending(callback) {
    chrome.storage.local.get(STATE_KEY, (data) => {
      const pending = data[STATE_KEY];
      if (!pending?.caseId) {
        callback(null);
        return;
      }
      if (isExpired(pending)) {
        chrome.storage.local.remove(STATE_KEY, () => callback(null));
        return;
      }
      callback(pending);
    });
  }

  function isExpired(pending) {
    const started = Date.parse(pending.startedAt || '');
    return !Number.isFinite(started) || Date.now() - started > MAX_PENDING_MS;
  }

  function mountCaptureButton(pending) {
    if (document.getElementById('food-app-mfp-capture-root')) return;
    const root = document.createElement('div');
    root.id = 'food-app-mfp-capture-root';
    root.innerHTML = `
      <button id="food-app-mfp-capture-btn" type="button">Capture for Food App</button>
      <button id="food-app-mfp-clear-btn" type="button">Clear pending</button>
      <div id="food-app-mfp-capture-hint">${escapeHtml(pending.foodText || 'Benchmark case')}</div>
    `;
    document.documentElement.appendChild(root);
    injectStyles();
    document.getElementById('food-app-mfp-capture-btn')?.addEventListener('click', () => openReviewModal(pending));
    document.getElementById('food-app-mfp-clear-btn')?.addEventListener('click', clearPendingCapture);
  }

  function clearPendingCapture() {
    chrome.storage.local.remove(STATE_KEY, () => {
      document.getElementById('food-app-mfp-capture-root')?.remove();
      document.getElementById('food-app-mfp-review-modal')?.remove();
    });
  }

  function openReviewModal(pending) {
    document.getElementById('food-app-mfp-review-modal')?.remove();
    const capture = extractNutrition();
    const modal = document.createElement('div');
    modal.id = 'food-app-mfp-review-modal';
    modal.innerHTML = `
      <div class="food-app-mfp-card" role="dialog" aria-modal="true" aria-label="Review MyFitnessPal capture">
        <div class="food-app-mfp-header">
          <div>
            <div class="food-app-mfp-kicker">Food App benchmark capture</div>
            <h2>Review MFP result</h2>
          </div>
          <button class="food-app-mfp-close" type="button" aria-label="Close">x</button>
        </div>
        <div class="food-app-mfp-context">
          <div><strong>Capturing for:</strong> ${escapeHtml(pending.foodText || 'Benchmark case')}</div>
          ${referenceSummary(pending.reference)}
          <div class="food-app-mfp-url">${escapeHtml(location.href)}</div>
        </div>
        <div id="food-app-mfp-warning" class="food-app-mfp-warning" style="display:none;"></div>
        <label>Item name<input id="food-app-mfp-name" value="${escapeAttr(capture.itemName)}" /></label>
        <div class="food-app-mfp-grid">
          <label data-field="calories">Calories<input id="food-app-mfp-calories" type="number" min="0" step="0.1" value="${capture.calories ?? ''}" /></label>
          <label data-field="protein">Protein<input id="food-app-mfp-protein" type="number" min="0" step="0.1" value="${capture.protein ?? 0}" /></label>
          <label data-field="carbs">Carbs<input id="food-app-mfp-carbs" type="number" min="0" step="0.1" value="${capture.carbs ?? 0}" /></label>
          <label data-field="fat">Fat<input id="food-app-mfp-fat" type="number" min="0" step="0.1" value="${capture.fat ?? 0}" /></label>
        </div>
        <label>Serving<input id="food-app-mfp-serving" value="${escapeAttr(capture.servingLabel)}" placeholder="Optional serving shown on MFP" /></label>
        <label>Notes<textarea id="food-app-mfp-notes" rows="3" placeholder="Why this MFP result is the fair comparison.">${escapeHtml(capture.notes)}</textarea></label>
        <label id="food-app-mfp-verify-wrap" class="food-app-mfp-verify" style="display:none;"><input id="food-app-mfp-verified" type="checkbox" /> I verified this suspicious capture is the correct MFP comparison.</label>
        <div class="food-app-mfp-footer">
          <span id="food-app-mfp-status">Confirm the values before saving.</span>
          <button id="food-app-mfp-save" type="button">Use this MFP result</button>
        </div>
      </div>
    `;
    document.documentElement.appendChild(modal);
    modal.querySelector('.food-app-mfp-close')?.addEventListener('click', () => modal.remove());
    modal.querySelector('#food-app-mfp-save')?.addEventListener('click', () => saveReviewedCapture(pending, modal));
    modal.querySelectorAll('input, textarea').forEach((input) => input.addEventListener('input', () => updateReviewState(modal, pending)));
    updateReviewState(modal, pending);
  }

  function referenceSummary(reference) {
    if (!reference || reference.calories === undefined || reference.calories === null) return '';
    return `<div><strong>Reference:</strong> ${escapeHtml(reference.calories)} cal · P ${escapeHtml(reference.protein ?? 0)} · C ${escapeHtml(reference.carbs ?? 0)} · F ${escapeHtml(reference.fat ?? 0)}</div>`;
  }

  function updateReviewState(modal, pending) {
    const save = modal.querySelector('#food-app-mfp-save');
    const status = modal.querySelector('#food-app-mfp-status');
    const calories = numberValue(modal, '#food-app-mfp-calories');
    const itemName = value(modal, '#food-app-mfp-name');
    const caloriesLabel = modal.querySelector('[data-field="calories"]');
    const warning = modal.querySelector('#food-app-mfp-warning');
    const verifyWrap = modal.querySelector('#food-app-mfp-verify-wrap');
    const verified = Boolean(modal.querySelector('#food-app-mfp-verified')?.checked);
    const missingCalories = calories === null;
    const hardBlocks = hardBlockReasons();
    const warnings = suspiciousCaptureReasons({ itemName, calories, reference: pending?.reference });
    const allMessages = [...hardBlocks, ...warnings];
    const requiresVerification = warnings.length > 0;

    save.disabled = hardBlocks.length > 0 || missingCalories || (requiresVerification && !verified);
    caloriesLabel?.classList.toggle('food-app-mfp-missing', missingCalories);
    if (warning) {
      warning.style.display = allMessages.length ? 'block' : 'none';
      warning.innerHTML = allMessages.map(escapeHtml).join('<br>');
    }
    if (verifyWrap) verifyWrap.style.display = hardBlocks.length ? 'none' : requiresVerification ? 'flex' : 'none';
    status.textContent = hardBlocks.length
      ? 'Open a specific MFP food result before saving.'
      : missingCalories
      ? 'Calories were not detected. Enter calories to save.'
      : requiresVerification && !verified
        ? 'This capture looks suspicious. Verify before saving.'
        : 'Confirm the values before saving.';
  }

  function hardBlockReasons() {
    const reasons = [];
    if (/\/food\/search\b/i.test(location.pathname) && !getNutritionFactsScope()) {
      reasons.push('This is a MyFitnessPal search/results page. Open Nutrition info for a specific matching food before capturing.');
    }
    return reasons;
  }

  function suspiciousCaptureReasons({ itemName, calories, reference }) {
    const reasons = [];
    if (looksLikeUiText(itemName)) {
      reasons.push(`Item name "${itemName || 'blank'}" looks like MyFitnessPal UI text, not a food item.`);
    }
    if (calories !== null && calories < 5) {
      reasons.push(`Captured calories are ${calories}, which is suspiciously low for most benchmark foods.`);
    }
    const referenceCalories = Number(reference?.calories);
    if (Number.isFinite(referenceCalories) && referenceCalories > 0 && calories !== null) {
      const deltaPct = Math.abs(calories - referenceCalories) / referenceCalories;
      if (deltaPct > 0.7) {
        reasons.push(`Captured MFP calories (${calories}) differ strongly from reference (${referenceCalories}).`);
      }
    }
    return reasons;
  }

  function looksLikeUiText(value) {
    return /^(add food|add food to|add food to breakfast|breakfast|lunch|dinner|snacks?|search|myfitnesspal|food search)$/i.test(clean(value));
  }

  function extractNutrition() {
    const factsScope = getNutritionFactsScope();
    const text = factsScope?.innerText?.replace(/\u00a0/g, ' ') || visibleText();
    const itemName = firstNonEmpty([
      factsScope ? nutritionFactsItemName(text) : '',
      document.querySelector('h1')?.textContent,
      document.querySelector('[data-testid*="food"] h1')?.textContent,
      document.querySelector('meta[property="og:title"]')?.getAttribute('content'),
      document.title?.replace(/\|.*$/, '').replace(/MyFitnessPal/i, '')
    ]) || 'MyFitnessPal food item';
    const servingLabel = findServingLabel(text);
    return {
      itemName: clean(itemName),
      calories: findNutrient(text, ['calories', 'calorie', 'energy']),
      protein: findNutrient(text, ['protein']),
      carbs: findNutrient(text, ['total carbohydrate', 'carbohydrate', 'carbohydrates', 'carbs']),
      fat: findNutrient(text, ['total fat', 'fat']),
      servingLabel: clean(servingLabel),
      sourceUrl: location.href,
      notes: 'Captured from visible MyFitnessPal page; manually reviewed before save.',
      collectedAt: new Date().toISOString()
    };
  }

  function visibleText() {
    return (document.body?.innerText || '').replace(/\u00a0/g, ' ');
  }

  function getNutritionFactsScope() {
    const candidates = Array.from(document.querySelectorAll('div, section, table, article'));
    return candidates
      .filter((element) => {
        const text = element.innerText || '';
        return /Nutrition Facts/i.test(text)
          && /Calories/i.test(text)
          && /Protein/i.test(text)
          && /(Total Carbs|Total Carbohydrate|Carbs)/i.test(text);
      })
      .sort((a, b) => (a.innerText || '').length - (b.innerText || '').length)[0] || null;
  }

  function nutritionFactsItemName(text) {
    const lines = text.split('\n').map(clean).filter(Boolean);
    const index = lines.findIndex((line) => /^Nutrition Facts$/i.test(line));
    if (index < 0) return '';
    return lines.slice(index + 1).find((line) => {
      return !/^(Submitted on:|Confirmed by:|Is this data accurate\\?|Servings?:|Calories\\b)/i.test(line);
    }) || '';
  }

  function findServingLabel(text) {
    const direct = matchText(text, /(?:serving size|servings?)[\s:]+([^\n]{1,90})/i);
    if (direct) return direct;
    const lines = text.split('\n').map(clean).filter(Boolean);
    const index = lines.findIndex((line) => /serving size|servings?/i.test(line));
    if (index >= 0) return lines[index + 1] || '';
    return '';
  }

  function findNutrient(text, labels) {
    const lines = text.split('\n').map(clean).filter(Boolean);
    for (const label of labels) {
      const fromLines = findNutrientFromLines(lines, label);
      if (fromLines !== null) return fromLines;

      const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const patterns = [
        new RegExp(`${escaped}\\s*[:\\n ]+([0-9]+(?:\\.[0-9]+)?)\\s*(?:g|kcal|cal)?`, 'i'),
        new RegExp(`([0-9]+(?:\\.[0-9]+)?)\\s*(?:g|kcal|cal)?\\s+${escaped}`, 'i')
      ];
      for (const pattern of patterns) {
        const match = text.match(pattern);
        if (match?.[1] !== undefined) return Number(match[1]);
      }
    }
    return null;
  }

  function findNutrientFromLines(lines, label) {
    const labelRegex = new RegExp(`\\b${label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (!labelRegex.test(line)) continue;
      const sameLine = firstNumber(line.replace(labelRegex, ''));
      if (sameLine !== null) return sameLine;
      const nextLine = lines[index + 1] || '';
      const nextValue = firstNumber(nextLine);
      if (nextValue !== null) return nextValue;
    }
    return null;
  }

  function firstNumber(value) {
    const match = String(value || '').match(/([0-9]+(?:\.[0-9]+)?)/);
    return match ? Number(match[1]) : null;
  }

  function saveReviewedCapture(pending, modal) {
    const status = modal.querySelector('#food-app-mfp-status');
    const save = modal.querySelector('#food-app-mfp-save');
    const capture = {
      itemName: value(modal, '#food-app-mfp-name') || 'MyFitnessPal food item',
      calories: numberValue(modal, '#food-app-mfp-calories'),
      protein: numberValue(modal, '#food-app-mfp-protein') || 0,
      carbs: numberValue(modal, '#food-app-mfp-carbs') || 0,
      fat: numberValue(modal, '#food-app-mfp-fat') || 0,
      servingLabel: value(modal, '#food-app-mfp-serving') || null,
      sourceUrl: location.href,
      notes: value(modal, '#food-app-mfp-notes') || null,
      collectedAt: new Date().toISOString()
    };
    if (capture.calories === null) {
      updateReviewState(modal, pending);
      return;
    }
    const hardBlocks = hardBlockReasons();
    if (hardBlocks.length) {
      updateReviewState(modal, pending);
      return;
    }
    const warnings = suspiciousCaptureReasons({ itemName: capture.itemName, calories: capture.calories, reference: pending.reference });
    const verified = Boolean(modal.querySelector('#food-app-mfp-verified')?.checked);
    if (warnings.length && !verified) {
      updateReviewState(modal, pending);
      return;
    }
    save.disabled = true;
    status.textContent = 'Saving to Food App...';
    chrome.runtime.sendMessage({ type: 'FOOD_APP_MFP_SAVE', payload: { pending, capture } }, (response) => {
      if (response?.ok) {
        status.textContent = 'Saved. Refresh the benchmark dashboard to see the MFP values.';
        setTimeout(() => modal.remove(), 1200);
      } else {
        save.disabled = false;
        status.textContent = response?.error || 'Save failed.';
      }
    });
  }

  function value(root, selector) {
    return root.querySelector(selector)?.value?.trim() || '';
  }

  function numberValue(root, selector) {
    const raw = value(root, selector);
    if (!raw) return null;
    const parsed = Number(raw);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
  }

  function matchText(text, pattern) {
    return clean(text.match(pattern)?.[1] || '');
  }

  function firstNonEmpty(values) {
    return values.map(clean).find(Boolean) || '';
  }

  function clean(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function escapeHtml(value) {
    return String(value || '').replace(/[&<>"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[char]));
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/'/g, '&#39;');
  }

  function injectStyles() {
    if (document.getElementById('food-app-mfp-capture-styles')) return;
    const style = document.createElement('style');
    style.id = 'food-app-mfp-capture-styles';
    style.textContent = `
      #food-app-mfp-capture-root { position: fixed; right: 18px; bottom: 18px; z-index: 2147483647; width: 240px; padding: 12px; border-radius: 18px; background: rgba(12,14,20,0.92); color: #f8fafc; box-shadow: 0 18px 60px rgba(0,0,0,0.28); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      #food-app-mfp-capture-btn { width: 100%; border: 0; border-radius: 12px; padding: 10px 12px; font-weight: 800; color: white; background: linear-gradient(180deg, #818cf8, #4f46e5); cursor: pointer; }
      #food-app-mfp-clear-btn { width: 100%; margin-top: 7px; border: 1px solid rgba(255,255,255,0.12); border-radius: 10px; padding: 7px 10px; font-weight: 700; color: #cbd5e1; background: rgba(255,255,255,0.06); cursor: pointer; }
      #food-app-mfp-capture-hint { margin-top: 8px; font-size: 11px; color: #aab0d0; line-height: 1.35; }
      #food-app-mfp-review-modal { position: fixed; inset: 0; z-index: 2147483647; display: grid; place-items: center; background: rgba(4,6,12,0.55); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      .food-app-mfp-card { width: min(600px, calc(100vw - 32px)); border-radius: 22px; padding: 20px; background: #11131d; color: #f8fafc; border: 1px solid rgba(129,140,248,0.24); box-shadow: 0 24px 80px rgba(0,0,0,0.42); }
      .food-app-mfp-header, .food-app-mfp-footer { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
      .food-app-mfp-context { margin-top: 14px; padding: 11px 12px; border-radius: 14px; background: rgba(129,140,248,0.10); color: #dbe2ff; font-size: 12px; line-height: 1.45; }
      .food-app-mfp-url { margin-top: 3px; color: #94a3b8; word-break: break-all; }
      .food-app-mfp-warning { margin-top: 12px; padding: 10px 12px; border-radius: 14px; color: #fed7aa; background: rgba(249,115,22,0.14); border: 1px solid rgba(249,115,22,0.28); font-size: 12px; line-height: 1.45; }
      .food-app-mfp-kicker { color: #aab0d0; font-size: 11px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
      .food-app-mfp-card h2 { margin: 3px 0 0; font-size: 22px; }
      .food-app-mfp-close { border: 0; border-radius: 999px; width: 34px; height: 34px; background: rgba(255,255,255,0.08); color: #f8fafc; cursor: pointer; }
      .food-app-mfp-card label { display: flex; flex-direction: column; gap: 5px; margin-top: 12px; color: #aab0d0; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; }
      .food-app-mfp-card input, .food-app-mfp-card textarea { width: 100%; border: 1px solid rgba(129,140,248,0.24); border-radius: 12px; background: #1b2030; color: #f8fafc; padding: 10px 12px; font-size: 14px; }
      .food-app-mfp-verify { flex-direction: row !important; align-items: center; gap: 8px !important; color: #fed7aa !important; text-transform: none !important; letter-spacing: 0 !important; font-size: 12px !important; }
      .food-app-mfp-verify input { width: auto !important; }
      .food-app-mfp-missing input { border-color: rgba(239,68,68,0.76); box-shadow: 0 0 0 3px rgba(239,68,68,0.14); }
      .food-app-mfp-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
      #food-app-mfp-save { border: 0; border-radius: 13px; padding: 11px 14px; font-weight: 800; color: white; background: linear-gradient(180deg, #22c55e, #16a34a); cursor: pointer; }
      #food-app-mfp-save:disabled { cursor: not-allowed; opacity: 0.48; }
      #food-app-mfp-status { color: #aab0d0; font-size: 12px; }
      @media (max-width: 560px) { .food-app-mfp-grid { grid-template-columns: repeat(2, 1fr); } }
    `;
    document.documentElement.appendChild(style);
  }
})();
