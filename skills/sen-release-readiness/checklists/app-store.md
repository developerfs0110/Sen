# App Store & Google Play Store Release Checklist

> **Applicability:** Run this checklist when the project builds or ships a mobile or desktop store application (iOS App Store, Google Play Store, macOS App Store, Microsoft Store). If the project is not distributed through an app store, mark this domain `PASS (N/A)`.
>
> **Severity Key:** Unmet `[BLOCK]` items prevent store approval or cause immediate rejection and must mark the domain `BLOCK`. Unmet `[WARN]` items should be addressed soon but do not block initial release (`WARN`).

## Checklist Items

- [ ] **[BLOCK] Privacy Policy & Data Safety Disclosure:** A valid, publicly accessible Privacy Policy URL is configured in store metadata and linked inside the app, and all collected data types (location, identifiers, crash logs, analytics) match the App Privacy / Data Safety declarations.
- [ ] **[BLOCK] Runtime Permission Justification Strings:** Every platform permission requested (`Info.plist` `NS*UsageDescription` on iOS/macOS, `AndroidManifest.xml` permissions on Android) is strictly necessary for a user-facing feature and includes a clear, concrete purpose string.
- [ ] **[BLOCK] In-App Account Deletion:** If the app allows users to create an account, an easily discoverable in-app flow exists to permanently delete the user account and associated personal data (required by both Apple Guideline 5.1.1(v) and Google Play User Data policy).
- [ ] **[BLOCK] Digital Goods & Billing Compliance:** Any digital content, subscriptions, or in-app unlocks use the store's native billing API (StoreKit / Google Play Billing) where required by store guidelines, with a working "Restore Purchases" action.
- [ ] **[BLOCK] Target SDK & Minimum OS Compliance:** Android `targetSdkVersion` / `compileSdkVersion` and iOS SDK / Xcode build versions meet the current minimum store submission requirements.
- [ ] **[BLOCK] Release Signing & Production Entitlements:** Release builds are signed with production distribution certificates/keystores (no debug flags, no test-only entitlements, and no hardcoded staging URLs in release build variants).
- [ ] **[BLOCK] No Placeholder or Broken UI Flows:** All screens, buttons, and links reachable by a store reviewer work without placeholder text ("Lorem ipsum", "TODO"), broken links, or hidden beta switches.
- [ ] **[WARN] Reviewer Demo Credentials & Instructions:** If any part of the app requires sign-in, hardware pairing, or geo-restricted access, dedicated non-2FA demo credentials and clear step-by-step review notes are prepared.
- [ ] **[WARN] App Icons, Launch Screens & Store Screenshots:** All required app icon sizes, adaptive icons, launch screens, and store listing screenshots are present at the required resolutions without stretching or debug banners.
- [ ] **[WARN] Age Rating & Content Moderation:** Content rating questionnaires are accurately completed, and any user-generated content (UGC) features include reporting, blocking, and terms-of-use acceptance flows.
