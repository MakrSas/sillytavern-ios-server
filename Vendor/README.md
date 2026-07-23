# NodeMobile runtime

`NodeMobile.xcframework` intentionally is not stored in Git.

- `scripts/prepare-node18-runtime.sh` downloads the published NodeMobile 18.20.4 artifact and verifies its pinned SHA-256.
- `.github/workflows/build-node22-and-ipa.yml` builds the experimental Node 22 mobile fork and places the resulting XCFramework here before building the app.
