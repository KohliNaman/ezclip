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

`./Scripts/build-release.sh` automatically uses `ezclip dev` when present and falls back to the repo's default signing when it is missing.

To use a different identity:

```sh
EZCLIP_DEV_SIGN_IDENTITY="My Signing Cert" ./Scripts/build-release.sh
```

Keep `PRODUCT_BUNDLE_IDENTIFIER` locked to `com.namaankohli.ezclip`. If you reset TCC with `tccutil`, macOS will ask once again, but normal rebuilds should keep permissions.
