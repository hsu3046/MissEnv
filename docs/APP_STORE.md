# Mac App Store submission

## App record

- Name: MissEnv
- Platform: macOS
- App Store Connect app ID: 6818769037
- Bundle ID: vote.aib.missenv
- Version: 0.1.0 / build 1
- Primary category: Developer Tools
- Secondary category: Productivity (optional)
- Developer / copyright: AIB Inc. / © 2026 AIB Inc.
- License: MIT
- Price: Free (175 countries and regions)
- Primary language: Korean
- Support URL: https://github.com/hsu3046/MissEnv/issues
- Privacy policy URL: https://github.com/hsu3046/MissEnv/blob/main/docs/PRIVACY.md
- Marketing URL: https://www.aib.vote
- Subtitle: 프로젝트 환경변수를 한곳에서
- Keywords: 환경변수,env,dotenv,개발자,프로젝트,파일,비교,설정

## Description draft

MissEnv는 프로젝트마다 흩어진 .env 파일을 한곳에서 검색하고 편집하고 비교하는 macOS 앱입니다.

폴더를 등록하면 하위 프로젝트의 환경변수 파일을 찾아줍니다. 전체 환경변수 목록에서 같은 변수명을 사용하는 프로젝트와 값별 사용처를 확인하고, 이름이 달라도 같은 값을 쓰는 변수를 찾을 수 있습니다.

변수를 인라인으로 편집하거나 원본을 수정하고, 같은 프로젝트의 환경 파일을 나란히 비교하세요. 원본이 외부에서 변경되면 덮어쓰기를 차단하며 저장 전 이전 파일을 백업합니다.

계정·서버·광고 없이 로컬에서 동작합니다. 환경변수 파일과 값은 외부로 전송하지 않습니다. MIT 라이선스로 소스 코드를 공개합니다.

주요 기능: 하위 프로젝트 탐색 / 변수명 검색 / 프로젝트 간 공유 값 확인 / 값 차이와 빈 값 필터 / 인라인 및 원본 편집 / 파일 비교 / 저장 전 변경 확인 / 자동 원본 백업.

## Review notes draft

No account, login, payment, server, or special hardware is required. Select a local project folder using the + button. For safe testing, create a folder containing package.json and a .env file with invented entries such as DEMO_URL=https://example.invalid and DEMO_FLAG=true. The app accesses user-selected files and stores local folder bookmarks. All values stay local. Every save creates a local backup beside the source file. The comparison feature uses another env file in the same project. Environment values are treated as literals and never executed.

## Submission requirements and status

The current direct build is not an App Store submission. The App Store target must use App Sandbox with user-selected read/write and app-scope bookmarks, a registered App ID, an appropriate App Store distribution certificate/profile, and a signed archive. Developer ID Application signing is for distribution outside the App Store.

Use MissEnv.xcodeproj / MissEnv scheme, select the AIB Inc. team, confirm automatic signing, archive, and validate before upload. Exercise folder selection, relaunch/bookmark restoration, nested env discovery, saving/backups, and Finder reveal in the sandboxed build. Screenshots must use invented values and the submitted build. Confirm privacy answers, age rating, free availability and contact information in App Store Connect. The privacy draft assumes the unchanged local-only app; re-evaluate if networking/analytics is added.

As of 2026-10-03, the AIB Inc. app record has been created and version 0.1.0 (build 1) was archived for arm64 and x86_64, exported with cloud-managed Apple Distribution signing, validated without errors, and uploaded successfully. App Store Connect processed the build and it is attached to the version. Korean metadata, three screenshots using invented values, age rating 4+, review contact, no-encryption answers, free worldwide availability, and the data-not-collected privacy label have been saved. Release is manual after approval.

An isolated ad-hoc app with the same sandbox entitlements was exercised with invented files: folder selection, nested discovery, inline editing, original save and backup, relaunch/bookmark restoration, and comparison. This does not claim that the store-signed binary was run locally. Apple confirmed receipt of the submission on 2026-10-03; the status is Waiting for Review. App Store approval and public store availability are still pending. Legal agreements and any enrollment/payment steps require the account holder's authorization.

## Primary references

- https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution
- https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/
- https://developer.apple.com/help/account/create-certificates/certificates-overview
