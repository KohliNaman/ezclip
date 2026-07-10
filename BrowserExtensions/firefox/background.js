const HOST = "com.namaankohli.ezclip";
const api = typeof browser !== "undefined" ? browser : chrome;
const EXTENSION_ID = "ezclip-design-context@namaankohli.com";

async function sourceBrowser() {
  try {
    const info = await api.runtime.getBrowserInfo();
    return /zen/i.test(info?.name || "") ? "zen" : "firefox";
  } catch (_) {
    return "firefox";
  }
}

async function withMetadata(payload, status = "ok", error = null) {
  return {
    ...payload,
    schemaVersion: 1,
    sourceBrowser: await sourceBrowser(),
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

async function sendNative(payload) {
  try {
    await api.runtime.sendNativeMessage(HOST, payload);
  } catch (error) {
    console.warn("ezclip native messaging failed:", error?.message || error);
  }
}

async function captureActiveTab(tabId) {
  if (!tabId) return;
  try {
    await api.tabs.executeScript(tabId, { file: "extractor.js" });
    const [payload] = await api.tabs.executeScript(tabId, { code: "ezclipExtractDesignContext();" });
    if (payload?.url) await sendNative(await withMetadata(payload));
  } catch (error) {
    try {
      const tab = await api.tabs.get(tabId);
      if (!tab?.url) return;
      await sendNative(await withMetadata({
        url: tab.url,
        title: tab.title || "",
        fonts: [],
        colors: [],
        cssTokens: [],
        buttons: [],
        fontFaceCSS: ""
      }, "restrictedPage", error?.message || "Extension could not inspect this page."));
    } catch (_) {
      // Browser pages can hide tab details as well.
    }
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
