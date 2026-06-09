// ezclip background script
// Polls localhost:19843/status every ~3 seconds. When capture is pending,
// asks the active tab's content script to extract design tokens, then POSTs
// the result to /context.

const STATUS_URL = "http://localhost:19843/status";
const CONTEXT_URL = "http://localhost:19843/context";
const ALARM_NAME = "ezclip-poll";
const POLL_INTERVAL_MINUTES = 3 / 60; // 3 seconds

// Create the repeating alarm on install / startup
browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) {
    pollStatus();
  }
});

browser.runtime.onStartup.addListener(() => {
  browser.alarms.create(ALARM_NAME, { periodInMinutes: POLL_INTERVAL_MINUTES });
});

browser.runtime.onInstalled.addListener(() => {
  browser.alarms.create(ALARM_NAME, { periodInMinutes: POLL_INTERVAL_MINUTES });
});

// Also poll immediately when the extension loads
browser.alarms.create(ALARM_NAME, { periodInMinutes: POLL_INTERVAL_MINUTES });
pollStatus();

async function pollStatus() {
  try {
    const response = await fetch(STATUS_URL, { method: "GET", cache: "no-store" });
    if (!response.ok) return;
    const data = await response.json();
    if (data && data.capturePending === true) {
      await triggerCapture();
    }
  } catch (err) {
    // localhost unreachable — app not running. Silently ignore.
  }
}

async function triggerCapture() {
  try {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tabs || tabs.length === 0) return;
    const tab = tabs[0];
    // Skip non-HTTP(S) tabs (e.g., about:, chrome://)
    if (!tab.url || (!tab.url.startsWith("http://") && !tab.url.startsWith("https://"))) {
      return;
    }
    const extracted = await browser.tabs.sendMessage(tab.id, { action: "capture" });
    if (extracted) {
      await postContext(extracted);
    }
  } catch (err) {
    // Content script not injected, tab not ready, or other issue — ignore
  }
}

async function postContext(payload) {
  try {
    await fetch(CONTEXT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    // Silently ignore — app may not be running
  }
}
