(function installLimitPacerMod(config) {
  const existing = globalThis.__codexLimitPacerMod;
  if (existing?.version === config.version) {
    existing.refresh();
    return existing.getStatus();
  }
  existing?.destroy?.();

  const WEEK_SECONDS = 7 * 24 * 60 * 60;
  const WEEK_TOLERANCE_SECONDS = 60;
  const widgetId = config.widgetId;
  const resetLabelId = widgetId + '-reset';
  const styleId = config.styleId;
  const neutralTolerance = config.neutralTolerance;

  let observer = null;
  let refreshTimer = null;
  let usageTimer = null;
  let usageRequest = null;
  let destroyed = false;
  let widget = null;
  let resetLabel = null;
  let usageSnapshot = null;
  let usageError = null;
  let status = {
    state: 'waiting-for-account-menu',
    version: config.version,
  };

  const patterns = {
    accountUsage: [/^usage$/i, /^nutzung$/i],
  };

  function cleanText(value) {
    return String(value ?? '')
      .replace(/[\u00a0\u202f\u2009]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function round(value) {
    return Math.round(clamp(value, 0, 100));
  }

  function visible(element) {
    if (!(element instanceof HTMLElement)) return false;
    const rect = element.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0.01;
  }

  function collectTextNodes(root = document.body) {
    if (!root) return [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || parent.closest('#' + widgetId)) return NodeFilter.FILTER_REJECT;
        return cleanText(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      },
    });
    const result = [];
    let node;
    while ((node = walker.nextNode())) result.push(node);
    return result;
  }

  function exactTextElements(patternList) {
    const result = [];
    const seen = new Set();
    for (const node of collectTextNodes()) {
      const text = cleanText(node.nodeValue);
      if (!patternList.some((pattern) => pattern.test(text))) continue;
      const element = node.parentElement;
      if (element && visible(element) && !seen.has(element)) {
        seen.add(element);
        result.push(element);
      }
    }
    return result;
  }

  function textWithoutWidget(root) {
    return cleanText(collectTextNodes(root).map((node) => node.nodeValue).join(' '));
  }

  function findCompactUsageRow() {
    const candidates = [];
    for (const label of exactTextElements(patterns.accountUsage)) {
      let element = label;
      for (let depth = 0; element && element !== document.body && depth < 9; depth += 1, element = element.parentElement) {
        if (!visible(element)) continue;
        const rect = element.getBoundingClientRect();
        const text = textWithoutWidget(element);
        if (rect.width < 120 || rect.width > 520 || rect.height < 22 || rect.height > 72 || text.length > 100) continue;
        if (!/(?:^|\s)(?:100|\d{1,2})(?:[.,]\d+)?\s*%/.test(text)) continue;
        const labelRect = label.getBoundingClientRect();
        const containsLabel = labelRect.left >= rect.left - 1 && labelRect.right <= rect.right + 1;
        if (!containsLabel) continue;
        candidates.push({ row: element, label, score: rect.width * rect.height + depth * 120 });
      }
    }
    candidates.sort((a, b) => a.score - b.score);
    return candidates[0] ?? null;
  }

  function isGerman() {
    return document.documentElement.lang?.toLowerCase().startsWith('de') || exactTextElements([/^nutzung$/i]).length > 0;
  }

  function paceText(delta, german) {
    const amount = Math.round(Math.abs(delta));
    if (Math.abs(delta) <= neutralTolerance) return german ? 'Im Wochentempo' : 'On weekly pace';
    if (delta > 0) return german ? amount + ' pp schneller' : amount + ' pp faster';
    return german ? amount + ' pp darunter' : amount + ' pp below pace';
  }

  function readWeeklyUsage(payload) {
    const windows = [
      payload?.rate_limit?.primary_window,
      payload?.rate_limit?.secondary_window,
    ];
    const weekly = windows.find((window) => {
      const duration = Number(window?.limit_window_seconds);
      return Number.isFinite(duration) && Math.abs(duration - WEEK_SECONDS) <= WEEK_TOLERANCE_SECONDS;
    });
    if (!weekly) throw new Error('Weekly Codex limit was not returned');

    const usedPercent = Number(weekly.used_percent);
    const resetAtSeconds = Number(weekly.reset_at);
    const durationSeconds = Number(weekly.limit_window_seconds);
    if (!Number.isFinite(usedPercent)
      || !Number.isFinite(resetAtSeconds)
      || Math.abs(durationSeconds - WEEK_SECONDS) > WEEK_TOLERANCE_SECONDS) {
      throw new Error('Weekly Codex limit was invalid');
    }

    return {
      usedPercent: clamp(usedPercent, 0, 100),
      resetTimestamp: resetAtSeconds * 1000,
      windowDurationMs: durationSeconds * 1000,
    };
  }

  function readDesktopUsage() {
    const bridge = window.electronBridge;
    if (!bridge?.sendMessageFromView) {
      return Promise.reject(new Error('Codex desktop bridge is unavailable'));
    }

    const requestId = globalThis.crypto?.randomUUID?.() ?? ('codex-limit-pacer-' + Date.now() + '-' + Math.random());
    return new Promise((resolve, reject) => {
      let settled = false;
      let timeout = null;

      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        if (timeout) clearTimeout(timeout);
        window.removeEventListener('message', onMessage);
        if (error) reject(error);
        else resolve(value);
      };

      const onMessage = (event) => {
        const message = event.data;
        if (message?.type !== 'fetch-response' || message.requestId !== requestId) return;
        if (message.responseType !== 'success' || message.status < 200 || message.status >= 300) {
          finish(new Error('Codex usage request failed'));
          return;
        }
        try {
          finish(null, JSON.parse(message.bodyJsonString));
        } catch (error) {
          finish(error);
        }
      };

      window.addEventListener('message', onMessage);
      timeout = setTimeout(() => finish(new Error('Codex usage request timed out')), 5_000);
      Promise.resolve(bridge.sendMessageFromView({
        type: 'fetch',
        requestId,
        method: 'GET',
        url: '/wham/usage',
        headers: {
          'OAI-Language': document.documentElement.lang?.split('-')[0] || navigator.language?.split('-')[0] || 'en',
          'X-OpenAI-Attach-Auth': '1',
          'X-OpenAI-Attach-Integrity-State': '1',
          originator: 'Codex Desktop',
        },
      })).catch((error) => finish(error));
    });
  }

  function refreshUsage() {
    if (destroyed || usageRequest) return;
    usageRequest = readDesktopUsage()
      .then(readWeeklyUsage)
      .then((nextSnapshot) => {
        usageSnapshot = nextSnapshot;
        usageError = null;
        refresh();
      })
      .catch((error) => {
        usageError = error instanceof Error ? error.message : String(error);
        refresh();
      })
      .finally(() => {
        usageRequest = null;
      });
  }

  function ensureUsageRefresh() {
    if (usageTimer !== null) return;
    refreshUsage();
    usageTimer = setInterval(refreshUsage, 60_000);
  }

  function elapsedPercent() {
    if (!usageSnapshot) return null;
    const startedAt = usageSnapshot.resetTimestamp - usageSnapshot.windowDurationMs;
    return clamp(((Date.now() - startedAt) / usageSnapshot.windowDurationMs) * 100, 0, 100);
  }

  function formatResetDate() {
    const locale = document.documentElement.lang || navigator.language || 'en-GB';
    const parts = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' })
      .formatToParts(new Date(usageSnapshot.resetTimestamp));
    return [parts.find((part) => part.type === 'day')?.value, parts.find((part) => part.type === 'month')?.value]
      .filter(Boolean)
      .join(' ');
  }

  function ensureStyle() {
    if (document.getElementById(styleId)) return;
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = [
      '#' + widgetId + ', #' + widgetId + ' * { box-sizing: border-box; }',
      '#' + widgetId + ' { display:block !important; grid-column:1 / -1 !important; width:100% !important; min-width:0 !important; align-self:stretch !important; margin:-1px 0 2px !important; padding:6px var(--cup-right, 12px) 7px var(--cup-left, 31px) !important; color:inherit !important; font:inherit !important; line-height:1.2 !important; background:transparent !important; border:0 !important; pointer-events:none !important; }',
      '#' + widgetId + ' .cup-line { display:flex !important; align-items:center !important; justify-content:space-between !important; gap:10px !important; margin:0 0 4px !important; min-height:15px !important; color:inherit !important; font-size:12px !important; font-weight:400 !important; letter-spacing:0 !important; opacity:.78 !important; }',
      '#' + widgetId + ' .cup-value { display:inline-flex !important; align-items:center !important; justify-content:flex-end !important; gap:5px !important; font-variant-numeric:tabular-nums !important; opacity:.95 !important; }',
      '#' + widgetId + ' .cup-track { position:relative !important; width:100% !important; height:4px !important; margin:0 0 6px !important; overflow:hidden !important; border-radius:999px !important; background:color-mix(in srgb, currentColor 13%, transparent) !important; }',
      '#' + widgetId + ' .cup-track:last-child { margin-bottom:0 !important; }',
      '#' + widgetId + ' .cup-fill { height:100% !important; border-radius:inherit !important; background:currentColor !important; opacity:.48 !important; transition:width 180ms ease-out !important; }',
      '#' + resetLabelId + ' { margin-left:4px !important; font:inherit !important; opacity:.72 !important; white-space:nowrap !important; pointer-events:none !important; }',
    ].join('\n');
    document.head.appendChild(style);
  }

  function ensureWidget() {
    if (widget?.isConnected) return widget;
    widget = document.createElement('div');
    widget.id = widgetId;
    widget.setAttribute('role', 'group');
    widget.innerHTML = [
      '<div class="cup-line"><span data-cup-label="elapsed"></span><span class="cup-value" data-cup-value="elapsed"></span></div>',
      '<div class="cup-track"><div class="cup-fill" data-cup-fill="elapsed"></div></div>',
      '<div class="cup-line"><span data-cup-label="used"></span><span class="cup-value" data-cup-value="used"></span></div>',
      '<div class="cup-track"><div class="cup-fill" data-cup-fill="used"></div></div>',
    ].join('');
    return widget;
  }

  function updateResetLabel(rowInfo) {
    if (!resetLabel?.isConnected) {
      resetLabel = document.getElementById(resetLabelId);
      if (!resetLabel) {
        resetLabel = document.createElement('span');
        resetLabel.id = resetLabelId;
      }
    }
    if (resetLabel.parentElement !== rowInfo.label) {
      rowInfo.label.appendChild(resetLabel);
    }
    resetLabel.textContent = ' (' + formatResetDate() + ')';
  }

  function updateWidget(rowInfo) {
    ensureStyle();
    updateResetLabel(rowInfo);
    const element = ensureWidget();
    if (element.previousElementSibling !== rowInfo.row || element.parentElement !== rowInfo.row.parentElement) {
      rowInfo.row.insertAdjacentElement('afterend', element);
    }

    const rowRect = rowInfo.row.getBoundingClientRect();
    const labelRect = rowInfo.label.getBoundingClientRect();
    const containerRect = rowInfo.row.parentElement?.getBoundingClientRect() ?? rowRect;
    const leftInset = clamp(labelRect.left - containerRect.left, 12, 80);
    element.style.setProperty('--cup-left', Math.round(leftInset) + 'px');
    element.style.setProperty('--cup-right', Math.max(10, Math.round(leftInset * 0.42)) + 'px');

    const german = isGerman();
    const used = usageSnapshot.usedPercent;
    const elapsed = elapsedPercent();
    const delta = used - elapsed;

    element.querySelector('[data-cup-label="elapsed"]').textContent = german ? 'Woche vergangen' : 'Week elapsed';
    element.querySelector('[data-cup-label="used"]').textContent = german ? 'Quota verbraucht' : 'Quota used';
    element.querySelector('[data-cup-value="elapsed"]').textContent = round(elapsed) + '%';
    element.querySelector('[data-cup-fill="elapsed"]').style.width = elapsed + '%';
    element.querySelector('[data-cup-value="used"]').textContent = round(used) + '%';
    element.querySelector('[data-cup-fill="used"]').style.width = used + '%';

    element.title = paceText(delta, german);
    status = {
      state: 'active',
      version: config.version,
      usedPercent: used,
      elapsedPercent: elapsed,
      delta,
      resetTimestamp: usageSnapshot.resetTimestamp,
      windowDurationMins: usageSnapshot.windowDurationMs / 60_000,
    };
  }

  function removeWidget() {
    widget?.remove();
  }

  function removeResetLabel() {
    resetLabel?.remove();
    resetLabel = null;
  }

  function refresh() {
    if (destroyed || !document.body) return status;
    const rowInfo = findCompactUsageRow();
    if (!rowInfo) {
      removeWidget();
      status = {
        state: 'waiting-for-account-menu',
        version: config.version,
      };
      return status;
    }

    ensureUsageRefresh();
    if (!usageSnapshot) {
      removeWidget();
      status = {
        state: usageError ? 'usage-unavailable' : 'loading-usage',
        version: config.version,
        error: usageError,
      };
      return status;
    }

    updateWidget(rowInfo);
    return status;
  }

  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(refresh, 80);
  }

  function destroy() {
    destroyed = true;
    clearTimeout(refreshTimer);
    clearInterval(usageTimer);
    observer?.disconnect();
    removeWidget();
    removeResetLabel();
    document.getElementById(styleId)?.remove();
    if (globalThis.__codexLimitPacerMod?.version === config.version) delete globalThis.__codexLimitPacerMod;
  }

  observer = new MutationObserver(scheduleRefresh);
  observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });

  globalThis.__codexLimitPacerMod = {
    version: config.version,
    refresh,
    destroy,
    getStatus: () => ({ ...status }),
  };
  return refresh();
})({
  version: '1.0.7',
  widgetId: 'codex-limit-pacer-widget',
  styleId: 'codex-limit-pacer-style',
  neutralTolerance: 4,
});
