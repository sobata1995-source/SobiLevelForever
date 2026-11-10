## 0.3.1-beta — XP/time forecast prioritization

- Add 2021 published quest XP rewards and conservative objective workload records.
- Rank comparable actionable nearby tasks by expected remaining XP/time, including
  kill XP, remaining objective counts, drop rates, level scaling and mesh walking
  distances through objectives to the hand-in.
- Obtain walking lengths asynchronously from the existing terrain router; no
  straight-line distance is presented as measured route length.
- Show Est. XP/min. Times are forecasts; no complete measured timing dataset exists here.
- Keep source priority when the baseline task has unknown work/path coverage.
- Keep dependency-preserving Speed policy, class milestones and escort restrictions.
- Record server XP rewards locally when the reward's character level is unambiguous.
- No static saved step reordering or quest abandonment. No global optimality claim.

## 0.3.0-beta — core quest speed policy, training evidence, floating arrow

- Enable dependency-preserving core-quest filtering by default; keep class quests,
  protected optional prerequisites and ready-to-turn-in rewards. No quests abandoned.
- Omit unrelated Camping/profession detours and their profession training steps.
- Keep class training on with Skip. Only an identified class trainer's complete
  catalogue can confirm training; store per-character evidence until the next
  catalogue level threshold, and invalidate it after class quest rewards.
- Unknown/hidden filters and mere trainer visits never count as completed training.
- Add a draggable floating walking arrow with saved screen position.
- Validate dependency closure across 90 test profiles plus trainer-state regressions.
- This is not a measured globally optimal XP/hour or live 1-60 benchmark.

## 0.2.0-beta — terrain-aware walking arrow

- Add an attributed standalone adaptation of Polestar 0.3.5's GPL-3.0-or-later
  walking router (derived from Shortest Path Forever) and its licensed map packs.
- Cover Zephras Isle, Eastern Kingdoms and Kalimdor; load continent data on demand.
- Use the next calculated path corner, remaining walking distance and ground/road
  costs instead of directing the arrow along the straight destination bearing.
- Recalculate after leaving the route; cancel stale jobs on destination change.
- Do not display a straight arrow while calculating or when no path is found.
- Check path distance for arrival so a nearby goal behind an obstacle is not
  automatically counted as reached. Same-continent zone boundaries are supported.
- Existing nearby quest ordering remains based on geometric estimates; no globally
  fastest journey, live obstacle changes or automatic cross-continent transport is claimed.
- Restart the game completely to discover the three newly installed addon folders.
- Tested adapter cancellation/corners/failure handling and actual synchronous/asynchronous
  path searches over the supplied Zephras Isle collision map outside the live client.

## 0.1.9-beta — nearby quest batching

- Group actionable objectives in the same map/area and show nearby quest names.
- Consider up to 160 upcoming source rows and 1200 yards; keep up to 12 candidate tasks.
- Prefer nearby active field work to a distant hand-in; allow adjacent hub interactions.
- Use world-coordinate distances, a nearest-neighbor queue and two local path-improvement passes.
- Keep the current target stable with a 90-yard switching margin and group tasks within 220 yards.
- Respect quest prerequisites, objective/reward state, source filters, group settings and escort/manual boundaries.
- Preserve the saved source cursor; auto-completion comes from the game. Skip applies to the displayed task.
- Enabled by default. /lg smart off restores the original guide order; /lg smart on enables batching.
- Straight-line estimates do not include terrain, combat time, caves or travel networks. No claim of a globally fastest route.

## 0.1.4-beta — missing destination supplement

- Provide 122 per-objective positions for 92 previously unpositioned quest tasks.
- Classify 11 remaining whole-quest tasks as inventory/item actions with explicit instructions.
- Preserve distinctions between event points, spawn/collection areas and escort starting areas.
- Remember arrival at event starting areas across reloads; stop pointing back while escorting.
- Preserve specific item-use instructions, including feeding Kyle, rather than inferring combat from a DB objective type.
- Retain all original chapter/step IDs and order. Published source archive checksum verified.
- Data positions and mocked tests do not establish terrain-aware routing or live playthrough correctness.

## 0.1.3-beta — complete bundled-route data audit

- Audit all 65 chapters, 9237 rows, 2045 quest IDs and all ten chains to level 60.
- Automatically track 36 quest conversations previously rendered as manual notes.
- Apply attributed factual corrections: 4 objective indexes, 19 prerequisite records,
  80 instruction tips, 26 whole-quest target lists and 4 objective-position records.
- Resolve unfinished whole-quest tasks to known individual objective destinations.
- Explain item-start quests without inventing an NPC.
- Keep every original step ID and its position so saved progress remains compatible.
- See Data/Source/route-audit.json for evidence, changes and remaining coordinate gaps.
- Static/mocked validation is not a live 1-60 playthrough.

## 0.1.1-beta — quest-aware guidance

- Persist positively confirmed quest rewards per character across reloads.
- Recover unfinished quest objectives instead of navigating to an early turn-in.
- Automatically restore the hand-in destination when the quest becomes ready.
- Skip travel within a source block only when all its remaining quest tasks are positively satisfied.
- Show the in-game quest title, explicit accept/do/turn-in action, NPC, instructions and objective progress.
- Add class-specific Thendal trainer destinations; generic training reminders are opt-in with `/lg training on`.
- Enlarge the guide and arrow; show an explanation when navigation is unavailable.
- Preserve explicit Pause/Prev/Skip choices; do not count Done, abandonment or objective completion as a rewarded quest.
- Validate with mocked engine, API, lifecycle, navigation and UI regressions. Live client behavior still requires play testing.

# Changelog

## 0.1.0 beta â€” 2026-11-09

Initial test package for Blizzard World of Warcraft: Forever, Interface 16001.

- Original guide engine, native UI, navigation, login initialization and saved guide progress.
- Adapted Polestar guide data pinned to `e978e136279cf075eff34718f3ad5fd3dacba623`: 65 chapters and 10 faction/race starting paths joining shared chapter chains through level60.
- Quest-state progression with manual review/controls where data or conditions cannot establish completion.
- Persistent block conditions, read-only Sync scanning, alternative-quest closure handling across later stages, and profession requirement checks.
- Previous/next/done/skip, pause/resume, route selection, scale and position controls, local reports, and reset confirmation.
- Skipping an optional accept remembers the unaccepted quest and skips its later guide goals and unavailable dependent chain. Actual acceptance/turn-in takes precedence; Sync can reopen active quest goals. Ordinary Skip remains a one-step guide override and never abandons a game quest.
- Same-map straight-line navigation, native waypoint support, coordinate-conversion fallback, and respect for user waypoint ownership.
- Included source/provenance/license material, Bulgarian/English instructions, five local regression suites, and a live-client test matrix. The bundled local suites pass 369 focused checks; details and limits are in VALIDATION_BG.md.

This beta has not been validated by a live-client session or complete 1â€“60 playthrough in the development environment. Upstream route coverage does not include every new Forever zone or quest. Code/mock checks are separate from in-game route validation.

Copyright 2026 SobiLevel Forever contributors. GPL-3.0; see included licensing notices.
