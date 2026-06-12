# ezclip Browser Extensions

These unpacked extensions push active-tab design context to ezclip through the bundled native messaging host.

## Chromium: Chrome and Helium

Load `BrowserExtensions/chromium` as an unpacked extension.

- Chrome: `chrome://extensions`
- Helium: open the Chromium extensions page
- Required extension ID: `aneomelhkigghoclfgmpejhmpgogpfij`

The ID is pinned by the `key` field in `manifest.json` so the native messaging manifest can allow it.

## Firefox: Zen

Load `BrowserExtensions/firefox` as a temporary/add-on extension in Zen or Firefox.

- Zen: `about:debugging#/runtime/this-firefox`
- Extension ID: `ezclip-design-context@namaankohli.com`

ezclip writes native messaging manifests on launch for Chrome, Helium, Zen, and Firefox.
