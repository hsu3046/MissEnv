# MissEnv development

- Native macOS 14+ application, Swift 6, SwiftUI/AppKit. No third-party runtime dependencies.
- Bundle ID: vote.aib.missenv. Copyright AIB Inc. (https://www.aib.vote), MIT License.
- Original env files are the source of truth. Never persist or log variable values in the registry.
- Preserve exact UTF-16 source coordinates, comments, duplicates, order and line endings.
- Never reload a dirty document automatically. Compare original bytes and back up before save.
- Keep discovery project identities canonical; do not count registered scan roots as projects.
- Validate with swift test and scripts/build.sh. UI tests use invented fixtures only.
- Mac App Store distribution uses MissEnv.xcodeproj and resources/MissEnv.entitlements; validate sandboxed file access before submission.
