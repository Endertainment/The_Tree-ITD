# Release checklist — 0.1.0 closed test

Status of every item needed before the closed test goes live, and everything
that must still change before production. `[x]` = done and observed in this
project; `[ ]` = still required.

## Build and signing

- [x] `application/config/version = "0.1.0"` in `project.godot`.
- [x] `version/name = "0.1.0"`, `version/code = 1` in `export_presets.cfg`.
- [x] Package `com.endertainment.thetree`, 64-bit ARM64, `targetSdk 35`,
      `minSdk 24` (from the export template).
- [x] Release keystore exists **outside the repository** at
      `C:\Users\VOVA\.the-tree\release.keystore`; credentials in
      `C:\Users\VOVA\.the-tree\release-keystore.txt` (not committed; `*.keystore`
      and `*.jks` are in `.gitignore`).
- [x] Keystore SHA-256 fingerprint:
      `7B:1D:D2:D9:45:B5:7B:E8:BF:50:9D:B1:F5:04:76:DC:DD:84:49:E1:52:AA:36:13:FD:E3:ED:29:10:A7:2F:22`.
- [x] AAB build preset `Android AAB` (Gradle, `export_format=1`) committed.
- [x] `tools/export_android.ps1 -Preset "Android AAB"` injects the keystore from
      `THE_TREE_KEYSTORE` / `_ALIAS` / `_PASSWORD` and restores the preset file.
- [ ] A signed AAB installs, launches **and carries its data** on a clean device. The first AAB installed as `0.1.0 (1)` but loaded no data (`ConfigDB` skipped `*.tres.remap`); the fix is in, the AAB is rebuilt, and re-installing on the test phone was blocked by Play Protect. Re-check on a device or through the Play closed track.

## Play Console

- [ ] App created with package `com.endertainment.thetree` and the 0.1.0 AAB
      uploaded to the **closed testing** track.
- [ ] Privacy policy URL published (required for the data-safety form).
- [ ] Data safety form completed: no data collected/shared, ads served by
      AdMob in the production build, purchases through Google Play.
- [ ] Ads declaration: contains ads (rewarded + interstitial) **once real ads are
      enabled**; this build shows no real ad and must not be submitted as-is.
- [ ] Content rating questionnaire completed (fantasy violence, no user
      generated content).
- [ ] Target API level meets the current Play requirement (35 at the time of
      writing); 64-bit ABI present; AAB upload accepted.
- [ ] `remove_ads` and one-time products declared as non-consumable; gem packs
      as consumable.

## Store assets

- [ ] Icon 512×512 PNG (generated from `icon.svg`, no alpha).
- [ ] Feature graphic 1024×500.
- [ ] 4–8 phone screenshots, portrait 1080×1920, English **and** Ukrainian.
- [ ] Short description (≤ 80 chars) and full description (≤ 4000 chars) in EN
      and UK.
- [ ] Category, tags, contact email, marketing URL.

## Closed testing

- [ ] Closed testing track with at least 12 testers and a working feedback
      channel (email or Discord).
- [ ] Tester instructions: how to install, what to try, where to report bugs.
- [ ] Rollout to 100% of the closed track.

## Before production

- [ ] Replace the fake ad provider with a real AdMob adapter and real unit IDs
      (`scripts/core/providers/admob_provider.gd`, `data/monetization/store_config.tres`).
- [ ] Replace the fake IAP provider with Play Billing and real product IDs
      (`scripts/core/providers/play_billing_provider.gd`, `data/shop/*.tres`).
- [ ] Add UMP consent flow and verify ads are not requested before consent.
- [ ] Verify `remove_ads` suppresses every interstitial and still grants the
      purchased entitlement after a reinstall (restore path).
- [ ] Verify purchases on a licensed tester account: buy, cancel, refund,
      restore, duplicate.
- [ ] Re-run `tools/simulate_balance.gd` after any balance change and re-read
      `docs/BALANCE_REPORT.md`.
- [ ] Fix the rendering budget (`docs/BACKLOG.md`) before marketing screenshots.
- [ ] Verify the oldest supported device: Vulkan presence, or ship a
      `gl_compatibility` export preset.
- [ ] Re-check the privacy policy and data safety answers after enabling real
      ad/billing SDKs.

## Signing key custody

The release key is the app's identity: every future update must be signed with
it. Keep `release.keystore` and its password in a password manager and at least
one offline backup. Losing both makes it impossible to update an installed app
under the same package name.
