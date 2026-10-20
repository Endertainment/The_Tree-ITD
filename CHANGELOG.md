# Changelog

All notable changes to The Tree — ITD are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versions.

## 0.1.0 — closed test (2026-10-20)

First closed-test build. Everything below is playable offline on a single
device; nothing is charged and no real ad is shown.

### What works

- **Boot and save** — boot splash, atomic JSON save at `user://save.json` with
  `save.bak`, corrupt-file recovery to `save.corrupt`, v1 → v2 migration and a
  tested "newer save is loaded, not destroyed" path.
- **Menu** — Home, Upgrades, Cards, Missions, Shop and Settings; equip up to two
  cards, claim daily and achievement rewards, switch EN/UK, mute audio, reset
  progress behind a confirmation.
- **Battle** — no-lane arena with steering orcs, a shooting Tree with 2-5 elf
  archers, 8 fixed build pads, three tower types with three levels each, sell
  and target modes, 10 authored waves plus procedural waves, bosses every 10th
  wave with summons/enrage, wave modifiers, pause, 1x/1.5x/2x speed, quit.
- **Progression** — in-run upgrade panel (Tree/Archers/Towers), six in-run
  tracks, eight permanent Gold tracks, results screen with Gold/Gems payout,
  best wave, Elf Level.
- **Monetization** — rewarded ads (double Gold, speed trial, revive, free Gems)
  and the eight shop products run on fake providers. Every failure path
  (close, provider failure, timeout, double tap) is covered by a headless test.
- **Polish** — localization (EN/UK), placeholder art and synthesized audio,
  haptics, screen shake, particles, first-run tutorial, quality switch.

### Fixed in this build

- **Exported builds loaded no data.** Godot lists `*.tres.remap` in an exported
  project, and `ConfigDB` skipped those files, so the first signed AAB ran with
  no towers, waves, upgrades, cards, missions or shop items. The loader now
  resolves the remap name and warns when a data directory comes back empty.
- **Wave 11 difficulty cliff.** Authored waves ran at x1.0 and procedural wave
  11 jumped to `1.16^10` (~4.4x); the scaling curves now start at the authored
  band.
### Known limitations

- Placeholder art and audio; the tree, orcs, towers and UI are drawn in code or
  generated SVGs/WAVs.
- Ads and IAP are **fake providers** in this build. No real AdMob or Play
  Billing account is wired, no money moves, no ad is shown.
- English and Ukrainian only.
- No accounts, cloud save, leaderboards or analytics SDK.
- A run is not restored after the app is killed; only meta progress is saved.
- The `mobile` renderer (Vulkan) was verified on one device only.
- Rendering budget is missed: up to ~964 draw calls and ~971 nodes with 70
  enemies (target: < 120 draws, < 400 nodes). See `docs/BACKLOG.md`.
- Balance is validated by an analytical model, not by playtests. The model
  finds a hard wave-8 wall, a flat band through wave 20 and a winner-take-all
  Gold curve; see `docs/BALANCE_REPORT.md`.
- Wave 30 is reachable only with a near-maxed meta profile; it was not reached
  in the 8-run simulated profile.

### Disabled in this build

- Real ad unit IDs and real billing product IDs.
- Store submission, content rating and privacy declarations.

### Verification

`docs/QA_REPORT.md` records the 20-row matrix, including every row that is
`BLOCKED` because it needs an emulator, a second device, a real ad account or
licensed store testers.
