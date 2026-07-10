const HOST = "com.namaankohli.ezclip";
const SOURCE_BROWSER = "chromium";
const EXTENSION_ID = "aneomelhkigghoclfgmpejhmpgogpfij";

function withMetadata(payload, status = "ok", error = null) {
  return {
    ...payload,
    schemaVersion: 1,
    sourceBrowser: SOURCE_BROWSER,
    sourceExtensionId: EXTENSION_ID,
    extractedAt: new Date().toISOString(),
    transportStatus: status,
    transportError: error,
    counts: {
      fonts: payload?.fonts?.length || 0,
      colors: payload?.colors?.length || 0,
      cssTokens: payload?.cssTokens?.length || 0,
      buttons: payload?.buttons?.length || 0
    }
  };
}

function sendNative(payload) {
  chrome.runtime.sendNativeMessage(HOST, payload, () => {
    if (chrome.runtime.lastError) {
      console.warn("ezclip native messaging failed:", chrome.runtime.lastError.message);
    }
  });
}

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
    if (payload?.url) sendNative(withMetadata(payload));
  } catch (error) {
    chrome.tabs.get(tabId, (tab) => {
      if (chrome.runtime.lastError) return;
      if (!tab?.url) return;
      sendNative(withMetadata({
        url: tab.url,
        title: tab.title || "",
        fonts: [],
        colors: [],
        cssTokens: [],
        buttons: [],
        fontFaceCSS: ""
      }, "restrictedPage", error?.message || "Extension could not inspect this page."));
    });
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
