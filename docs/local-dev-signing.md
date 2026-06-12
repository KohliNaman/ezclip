# Local Development Signing

Use a persistent local code-signing identity so macOS TCC treats rebuilds as the same app and keeps Accessibility and Screen Recording grants.

## Create the Certificate

1. Open Keychain Access.
2. Choose Certificate Assistant > Create a Certificate.
3. Name it `ezclip dev`.
4. Set Identity Type to `Self Signed Root`.
5. Set Certificate Type to `Code Signing`.
6. Create it in the login keychain and trust it for code signing if prompted.

Verify it:

```sh
security find-identity -v -p codesigning
```

You should see an identity named `ezclip dev`.

## Build With It

For daily iteration, use the fast Debug build/install path:

```sh
./Scripts/build-dev.sh
```

It builds arm64 only, installs to `/Applications/ezclip.app`, opens the app, and automatically uses `ezclip dev` when present.

`./Scripts/build-release.sh` uses the same identity when present and creates the release DMG under `build/`.

To use a different identity:

```sh
EZCLIP_DEV_SIGN_IDENTITY="My Signing Cert" ./Scripts/build-dev.sh
```

Keep `PRODUCT_BUNDLE_IDENTIFIER` locked to `com.namaankohli.ezclip`. If you reset TCC with `tccutil`, macOS will ask once again, but normal rebuilds should keep permissions.
