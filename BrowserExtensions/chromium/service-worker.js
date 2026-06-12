const HOST = "com.namaankohli.ezclip";

async function captureActiveTab(tabId) {
  if (!tabId) return;
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId },
      files: ["extractor.js"]
    });
    const [context] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => ezclipExtractDesignContext()
    });
    const payload = context?.result || result?.result;
    if (payload?.url) chrome.runtime.sendNativeMessage(HOST, payload, () => void chrome.runtime.lastError);
  } catch (_) {
    // Restricted browser pages and extension pages are expected to fail.
  }
}

chrome.tabs.onActivated.addListener(({ tabId }) => captureActiveTab(tabId));
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.active) captureActiveTab(tabId);
});
chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  const [tab] = await chrome.tabs.query({ active: true, windowId });
  captureActiveTab(tab?.id);
});
chrome.action.onClicked.addListener((tab) => captureActiveTab(tab.id));
