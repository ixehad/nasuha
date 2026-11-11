# App Store checklist

Check this list before every submission. Guideline numbers refer to Apple's App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/ (re-read them before each release, because Apple changes them several times a year).

## Build requirements
- [x] Built with Xcode 26 or later and the iOS 26 SDK (required for uploads since 28 April 2026). Deployment target stays at iOS 17.
- [x] `ITSAppUsesNonExemptEncryption = NO` in Info.plist (export compliance).
- [x] App icon is 1024 × 1024 PNG with no transparency (Any, Dark, Tinted).
- [x] `PrivacyInfo.xcprivacy`: no tracking, no collected data, UserDefaults reason CA92.1.
- [x] The audio cache reads only whether a file exists and its size, so it needs no extra reason code. Add one (C617.1) if file timestamps are ever read.
- [x] No third-party SDKs except GRDB (which ships its own privacy manifest).

## Content and completeness
- [ ] **2.1 App completeness:** the app must have real content. With no curated sets every topic is hidden, and an empty app will be rejected. Ship 3–5 real sets per visible topic.
- [ ] **2.1:** no placeholder text, no "coming soon", no dead buttons. Run `python3 tools/build_content.py --release`: it fails if any sample set is still included.
- [ ] **2.1:** recitation stays hidden until `licenceCleared` is true for the reciter.
- [ ] **1.1.5 Accurate religious quotation:** Arabic from Tanzil and translations from QuranEnc, unchanged, with their versions shown. Check each asbab reference against the printed source before release.
- [ ] **5.2 Intellectual property:** keep the Tanzil credit (CC BY 3.0), follow QuranEnc's terms, keep the font licences, and get written permission for any recitation before it ships.
- [ ] **4.2 Minimum functionality / 4.3 Spam:** there are many Qur'an apps. The description and screenshots must lead with what is different: why and when each ayah was revealed, the ayahs around it, and topic-based reminders.

## Privacy
- [ ] **5.1.1 Privacy policy URL:** required for every app. Host the Legal page (for example on GitHub Pages) and put the URL in App Store Connect.
- [ ] App Privacy label in App Store Connect: "Data Not Collected".
- [x] No accounts, so the account-deletion rule (5.1.1(v)) does not apply.
- [ ] Recitation downloads audio files from the reciter's host when the user presses play. Nothing about the user is sent, but the host sees the request like any web server does. Say this in the privacy text.
- [ ] Ask for notification permission only after "Start my daily ayah", and the app must still work if the user says no.

## Payments
- [ ] **3.1.1:** tips must be StoreKit in-app purchases (consumables), with no links to outside payment. They unlock nothing.
- [ ] Hide the tip row when products fail to load.
- [ ] Tips need the Paid Apps agreement, plus banking and tax details, in App Store Connect.

## Background modes
- [x] **2.5.4:** `fetch` is used by the reminder refresh task.
- [ ] **2.5.4:** `audio` is declared for background recitation. If a release ships with no cleared reciter (audio hidden), remove `audio` from `UIBackgroundModes` in `project.yml` for that release, because the app would declare a mode it doesn't use.

## App Store Connect
- [ ] Apple Developer Program membership ($99 a year) on the account that will publish.
- [ ] Register the bundle ID `app.nasuha.ios`.
- [ ] Age rating questionnaire, including the newer questions (answers are required for new apps and updates). Expected: 4+.
- [ ] Name "Nasuha: Daily Quran Ayah" (30-character limit), subtitle "Reminders by Topic You Choose" (30), plus the Bangla localisation.
- [ ] Screenshots from the real app: 6.9" and 6.5" iPhone, light and dark.
- [ ] Support URL (for example the GitHub repo's issues page) and contact email.
- [ ] EU Digital Services Act: declare trader or non-trader status. Selling tips usually counts as trader, which means a public address and phone number.
- [ ] Review notes: explain that reminders are local, there's no login, and where the content comes from.
- [ ] Run a trademark search for "Nasuha" before release.
