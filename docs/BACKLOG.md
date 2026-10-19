# Backlog — known issues and deferred work

Everything found during the stage-8 QA pass that was **not** fixed, with the
evidence and the recommended next step. Fixed items are in the commit history;
this file only lists open work.

## Rendering budget

- **Measured:** at the 70-enemy stress case, `964` draw calls and `971` nodes at
  high quality, `469` draws at low quality (desktop RTX 3050, vsync-capped
  60 FPS). Budget is `< 120` draw calls and `< 400` nodes in battle
  (master §8.5); about `260` draws exist before the first enemy spawns.
- **Why not fixed:** the fix is a rendering refactor — `MultiMeshInstance2D` for
  orc bodies, lazy construction of the sheet scenes, merged static UI — which
  would touch the tested battle scene. Stage 8 is a bug-fix pass.
- **Next step:** move orc bodies and tower silhouettes to `MultiMeshInstance2D`,
  then re-run `TestSoak` and `BENCHMARK` (F2 → BENCHMARK in a debug build).

## Balance

See `docs/BALANCE_REPORT.md` for the numbers behind every item.

- **Wave 8–9 is a hard wall.** Both simulated profiles lose runs at wave 8 while
  player DPS is still 56–115. The authored spike (19 enemies, first `swift`
  modifier) lands before the economy can answer it. Recommendation: soften the
  authored waves 8–9 or move the first modifier later.
- **The curve flattens after wave 10.** Procedural waves 11–19 have less total
  HP than the authored wave 9, so a run that passes wave 8 usually coasts to
  wave 20+.
- **Gold is winner-take-all.** A run dying at wave 8 pays 112 Gold; a run
  passing it pays 1 600–2 000. That step, not smooth progression, is what moves
  the profile from wave 8 to wave 37.
- **Strategy spread.** An Archer Tower gives ~0.23 DPS per Coin, the first
  Canopy Bows level ~0.06. Tower-first play is worth ~2 waves on run 1 and ~10
  later. Either raise the early upgrade values or raise tower prices.
- **Boss HP growth is out of step with wave HP growth.** Boss HP is
  `1500 × 1.35^(index-1)` (2 734 at wave 30) while wave enemy HP is
  `1.16^step × base` (~73 000 total at wave 30). Bosses become a speed bump.
- **Wave 30 needs a near-maxed profile.** The 8-run simulated profile reaches
  wave 39 at best; the remaining gap to wave 30 is meta Gold (≈200 000 total).
- **Authored waves stop at 10, not 30.** The master context plans authored waves
  1–30; the shipped table has 1–10 and everything after is procedural.
  `WaveRules.scaling_for_wave()` now offsets the curves to the authored band.

## Gameplay and stability

- **Steering stall warnings.** `TestSoak` prints
  `[Enemy] orc_runner stalled at (...), nudging` when the artificial mass-kill
  leaves orcs wedged against tower pads. The nudge recovers, but the underlying
  deadlock against obstacles is not fixed.
- **`ObjectDB` leak warnings at exit.** Most headless suites end with
  `2 ObjectDB instances were leaked at exit` and `1 resources still in use`.
  The count does not grow across runs (soak: `965 → 965` nodes, `0` orphans) and
  the lines come from engine teardown after `quit()`, not from gameplay code.
  Re-check with `--verbose` before production.
- **Mid-run state is not restored** after an app kill, by design (master §7.6).
  Testers will report this as lost progress; it is documented in the changelog.
- **No device coverage for tablets or 1080×2400.** One physical phone was
  tested; tablet and tall-screen layouts are unverified.

## Monetization

- **Real ad and billing SDKs are not wired.** `AdMobProvider` and
  `PlayBillingProvider` are reflection-guarded stubs; the build uses the fake
  providers. See `docs/RELEASE_CHECKLIST.md` → *Before production*.
- **No UMP consent flow.** Required before any real ad request in the EEA.
- **Restore is untested against a real store.** The fake provider reports owned
  products; Play Billing restore needs a licensed tester account.
