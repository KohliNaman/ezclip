const HOST = "com.namaankohli.ezclip";
const api = typeof browser !== "undefined" ? browser : chrome;

async function captureActiveTab(tabId) {
  if (!tabId) return;
  try {
    await api.tabs.executeScript(tabId, { file: "extractor.js" });
    const [payload] = await api.tabs.executeScript(tabId, { code: "ezclipExtractDesignContext();" });
    if (payload?.url) api.runtime.sendNativeMessage(HOST, payload).catch(() => {});
  } catch (_) {
    // Restricted browser pages and extension pages are expected to fail.
  }
}

api.tabs.onActivated.addListener(({ tabId }) => captureActiveTab(tabId));
api.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.active) captureActiveTab(tabId);
});
api.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === api.windows.WINDOW_ID_NONE) return;
  const tabs = await api.tabs.query({ active: true, windowId });
  captureActiveTab(tabs[0]?.id);
});
api.browserAction.onClicked.addListener((tab) => captureActiveTab(tab.id));
