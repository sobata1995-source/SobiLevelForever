# SobiLevel Forever: guide attribution and third-party notices

SobiLevel Forever uses an independently written addon runtime and user interface.
Its bundled leveling **guide data** is an adaptation of the free, GPL-licensed
Polestar project. It is not an original SobiLevel route and must not be represented
as one. No proprietary RestedXP guide content is included.

## Polestar guide data

- Project: **Polestar**, by **The Polestar authors and credited contributors**.
- Copyright: **Copyright (c) 2026 The Polestar authors**.
- Repository: <https://github.com/fitzforge/polestar>.
- Exact source commit: `e978e136279cf075eff34718f3ad5fd3dacba623`.
- Source branch when retrieved: `next`; source pack version: `0.3.5`.
- Source commit date: 2026-11-08; retrieved: 2026-11-09.
- License for the authored guide text and this derived guide pack:
  **GNU General Public License version 3 only (`GPL-3.0-only`)**.
- Original authored sources: the 65 `guides/forever/alliance/**/*.guide` and
  `guides/forever/horde/**/*.guide` files at that commit.
- Resolved quest identifiers, names, objectives, NPC positions and requirements:
  the Leveling records in `addon/Polestar_Guides_Alliance/Guides.lua` and
  `addon/Polestar_Guides_Horde/Guides.lua` at the same commit.
- Era coordinate frames: `addon/Polestar_Guides/MapFrames.lua` at the same commit.

The original copyright/license and original third-party notices are retained in:

- `Data/Licenses/Polestar-LICENSE.txt` — the upstream copyright notice and GPLv3.
- `Data/Licenses/Polestar-THIRD_PARTY.md` — the upstream source inventory and terms.
- `Data/Licenses/Polestar-GUIDE-LICENSE-DATA.txt` — the guide pack's data notices.
- `Data/Licenses/Polestar-LICENSE-EXCEPTION.md` — the original additional permission.
- `Data/Licenses/CC-BY-4.0.txt` — the CC BY 4.0 text for credited factual inputs.

Polestar's guide-pack exception explicitly excludes text copied from its own
guides. **This adaptation uses the GPLv3 license, not that exception**, and the
whole SobiLevel distributable is supplied as GPLv3. The original notices also
describe Polestar components that are not included here; their presence as a
preserved notice does not imply that those components ship in SobiLevel.

## Factual reference data credited by the source guide pack

The copied guide-data notices identify all upstream factual inputs and their
revisions. These include CMaNGOS classic-db, EG Link output from Efficient Games
(CC BY 4.0), Factoruide, pfQuest by Shagu (MIT), Questie/QuestieDB, Forever
TrinityCore, recorded Forever observations, and Blizzard game facts. Original
notices and links are retained without reclassifying an input's own license as
GPL. The guide pack is an authored GPL work containing these interoperability
facts; SobiLevel does not redistribute the underlying third-party databases,
private navigation maps, proprietary addon code, or Blizzard art.

In particular, upstream marks some factual sources `NOASSERTION` or records no
separate data license. SobiLevel preserves that qualification and the attribution;
it does not claim a new license over those sources. Refer to the original
`Polestar-GUIDE-LICENSE-DATA.txt` and `Polestar-THIRD_PARTY.md` for precise terms,
attribution, and source boundaries. EG Link data is credited to Efficient Games,
<https://efficient.games>, from
<https://github.com/JIVESCORP/eg-link-output-wowf>, under
<https://creativecommons.org/licenses/by/4.0/>. Changes consist of extracting the
leveling facts and converting them into the SobiLevel schema as described below.

## Changes made for SobiLevel Forever

The adaptation, dated **2026-11-09**, is distributed under GPL-3.0-only with the
same absence of warranty as the original license:

1. Extracted only the 65 leveling chapters from the compiled data. Other guide
   categories, the Polestar engine, UI, media and navigation implementation are
   not part of this adaptation.
2. Converted source blocks into individual action rows. Resolved the source's
   named tokens into the included English text. Retained quest IDs, objective
   indices, prerequisites, quest-closing alternatives, class/race restrictions,
   group choices, coordinates, fractional level targets, and source notes.
3. Converted percent coordinates to 0–1 values. For Era-frame coordinates,
   derived world positions from the included source bounds so the addon can
   ask the current client for the correct live map position.
4. Converted seven background objectives from six source blocks into an early
   travel reminder and a completion checkpoint at their original later label.
5. Replaced four intentional-death travel shortcuts with ordinary travel to the
   same destination. These modified steps contain no instruction to die.
6. Removed eight unreachable rows in a Night Elf-only chapter whose source
   filters selected only Dwarves and Gnomes. Their originals remain in the source.
7. Presented travel services, training, item use without an observable quest
   objective, and advisory actions as manual checkpoints. The SobiLevel runtime
   determines which supported quest/level/position actions can advance from game
   evidence. It does not simulate the original Polestar engine.

The exact list of modifications and structural validation results is in
`Data/Source/validation.json`. This records **65 chapters, 9,237 action rows,
2,045 unique quest IDs and 10 race/faction starts reaching a level-60 terminal
chapter**. These are data counts, not a claim that every route has been played
through or tested in the live client.

## Corresponding editable source and reproduction

- `Data/Source/guides/` contains the 65 original `.guide` files, byte-for-byte
  matching the pinned upstream blobs.
- `Data/Source/polestar-leveling.json` preserves the extracted original compiled
  leveling tables as editable data, including fields not used by this runtime.
- `Data/Source/map-frames.json` contains the source Era frame bounds.
- `Data/Source/convert_routes.py` is the SobiLevel data converter.
- `Data/Source/PIN.json` names original paths, commit/blob IDs and bundled hashes.
- `Data/Source/normalized-routes.json` is a readable machine-data view of the
  generated Lua table; it is not loaded by the addon.

From the addon directory, regenerate the data with:

```text
python Data/Source/convert_routes.py
```

Only Python's standard library is needed. Edit the JSON input for a direct
SobiLevel data correction and run the converter; use the original Polestar
repository and its build instructions if rebuilding its `.guide` compilation.

The data conversion and structural checks do not substitute for testing on
Blizzard WoW Forever. The bundled source was a beta snapshot; new or changed
quests and zones can need updates. World of Warcraft and Blizzard Entertainment
are trademarks of Blizzard Entertainment. SobiLevel is not affiliated with or
endorsed by Blizzard Entertainment, RestedXP or the Polestar authors.


## SobiLevel 0.1.3 factual corrections

Additional attributed data records from fitzforge/polestar revision
cafeb253903d49c5d0e65fdc90bd4425d29d35c9:
- forever-db/corrections/quests.json -> Data/Source/quest-corrections.json
- data/guide-fixes.json -> Data/Source/guide-corrections.json

Upstream: https://github.com/fitzforge/polestar/tree/cafeb253903d49c5d0e65fdc90bd4425d29d35c9
The original records retain their contributor/source references, including Efficient Games
CC BY 4.0 records. See Data/Licenses/CC-BY-4.0.txt and the original source attribution
above. Corrections are applied by Data/Source/audit_routes.py; the change ledger is
Data/Source/route-audit.json. No upstream runtime code is imported by this update.


## SobiLevel 0.1.4 coordinate data supplement

Selected factual records from the Polestar 0.3.5 release's Polestar_QuestDB
(Quests.lua, Npcs.lua, Objects.lua, Items.lua) are decoded into
Data/Source/coordinate-reference.json. The reference includes the source URL
and archive SHA256, checked against the release's published SHA256SUMS.
Full original third-party attribution: Data/Licenses/Polestar-QuestDB-LICENSE-DATA.txt.
No upstream runtime code is loaded or included by the coordinate builder.
Contextual task-area and inventory rules reference the previously bundled original guides.
Reproduce the supplement via Data/Source/convert_routes.py; inspect coordinate-audit.json.


## Terrain router (0.2.0)

Sibling addons SobiLevelNav, SobiLevelNav_EK and SobiLevelNav_Kalimdor contain a
standalone packaging adaptation of the corresponding Polestar_Nav addons from
https://github.com/fitzforge/polestar/releases/tag/v0.3.5 .
The original release archive SHA256 was verified against SHA256SUMS earlier in this task.
Router: Cillian Berragan / Shortest Path Forever and The Polestar authors.
Walking maps: Polestar / Leffe, with source attribution and permissions described
in SobiLevelNav/CREDITS.md. Licence: GPL-3.0-or-later (SobiLevelNav/LICENSE).
Modified identifiers: addon names, data/engine/chokepoint globals; removed the
Polestar core dependency and changed display titles/grouping. Algorithms and data
remain attributed upstream source. See SobiLevelNav/SOBILEVEL-ADAPTATION.json.
The SobiLevel TerrainRouter.lua adapter is original GPL-3.0-only code.


## Class trainer identities (0.3.0)

ClassTrainerIDs.lua contains factual NPC/class associations extracted from
Polestar 0.3.5's generated Core/ClassTrainers.lua. The original reference, including
its generation/CMaNGOS attribution, is retained in Data/Source/ClassTrainers-reference.lua.
No upstream trainer runtime is loaded. Trainer handling follows the Forever UI snapshot:
https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua
Events are specified in Blizzard_APIDocumentationGenerated/TrainerDocumentation.lua.


## XP/workload forecasts (0.3.1)

QuestEfficiencyData.lua derives factual quest XP/level fields from the Polestar
0.3.5 Codex Quests1.lua/Quests2.lua data and factual objective/drop records from
the bundled leveling export and QuestDB Items.lua/Quests.lua.
Full Codex attribution: Data/Licenses/Polestar-Codex-LICENSE-DATA.txt.
Full QuestDB attribution remains in Polestar-QuestDB-LICENSE-DATA.txt.
Reference values: Data/Source/quest-efficiency-reference.json.
Time constants (11 to 30 seconds per baseline kill, 6 seconds per interaction,
7 yards/second running, 4.3% extra kills) follow the published Polestar model and
rust/crates/forge-sim/src/params.rs at revision 0df6f58ab8eeabb248153fdd889e64211177e279.
Kill XP and quest-level scaling follow that revision's forge-sim/src/xp.rs.
These are explicitly estimated durations, not recorded quest completion times.
