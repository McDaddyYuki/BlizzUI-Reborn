# Provenance and licensing notes (0.7.0)

This is a factual record, not legal advice. BlizzUI Reborn is **all rights reserved** (see LICENSE); nothing here grants permission to reuse the code.

## Removed in 0.7.0

| What | Origin | Status |
|---|---|---|
| `TimelineData.lua`: 464 encounter records (creature IDs, spell IDs, opener and cooldown timings, enrage rules, labels, and which spells counted as important or dangerous) | Extracted from the **DBM-Warmane** boss modules (Zidras), a backport of **Deadly Boss Mods**. DBM's source files state: "The code of this addon is licensed under a Creative Commons Attribution-Noncommercial-Share Alike 3.0 License". DBM-Warmane shows no separate licence, so it presumably carries DBM's. | Deleted from the addon, the TOC and the release ZIP. No replacement dataset is bundled. Boss identity, importance and timings now come only from game flags, the player's decisions, live boss mod timers (not stored), and casts observed in the player's own fights. |
| `tools/extract_timeline.py` | Written for this project; it read DBM-Warmane's boss modules to build the file above. | Deleted, so the dataset can't be rebuilt from a boss mod install. |

**Historical attribution:** releases 0.5.0 to 0.6.1 bundled that dataset. Its source was Deadly Boss Mods (deadlybossmods.com, originally by Paul Emmerich "Tandanu" and Martin Verges "Nitram", with many contributors), via DBM-Warmane by Zidras. Copies of those older ZIPs still contain it and remain subject to DBM's licence terms. Whether those older releases need any further notice is an open question (see below).

Saved variables written by 0.5.x–0.6.x never contained the dataset itself. They held observed samples, flags and boss confirmations. The 0.7.0 migration keeps those, clears validation scores that were computed against the dataset, and marks carried-over timings for re-checking. See CHANGELOG.md.

## Third-party interfaces still used (no third-party code is bundled)

The addon calls or reads these at runtime only when the other addon is installed. It does not modify their files, settings, timers or databases, and nothing received from them is stored.

- **Deadly Boss Mods** (3.3.5 backports with callbacks, such as DBM-Warmane):
  - `DBM:RegisterCallback` for `DBM_TimerStart/Stop/Update/Pause/Resume`, `DBM_Pull`, `DBM_SetStage`, `DBM_Kill`, `DBM_Wipe`;
  - `DBM:GetModByName(id)`;
  - the module fields `id`, `creatureId`, `multiMobPullDetection`, `combatInfo.mob`, `inCombat`, `isTrashMod`, `localization.general.name`.

  *Version-specific:* the callback argument order and these module fields are what DBM-Warmane uses. They were checked against the old test fakes, not against a live DBM install in this build.
- **BigWigs** (3.3.5):
  - the AceEvent-3.0 messages `BigWigs_OnBossEngage`, `BigWigs_StartBar`, `BigWigs_StopBar`, `BigWigs_StopBars`, `BigWigs_OnBossDisable`, `BigWigs_OnBossWin`, `BigWigs_OnBossWipe`;
  - `BigWigs:GetEnableMobs()`;
  - the module fields `moduleName` and `displayName`.

  *Version-specific and unverified* against a live 3.3.5 BigWigs in this build.
- **Ace3 / LibStub / AceEvent-3.0, LibDataBroker-1.1, LibDBIcon-1.0:** used through LibStub if another addon loaded them. Not bundled.
- **Carbonite:** `Nx.Map:GeM(1)`, its map window frames (`Win1.Frm`, `Frm`), the dock list `Nx.Map.Doc.MMF1`, the known-frame table `MMOF`, and `Nx.VERSION`. These are read, and the addon's own icons are taken out of the dock list. Carbonite's map and minimap are never moved, resized or re-parented.
- **Bagnon:** the inventory frame is looked up by name to place a currency strip under it.
- **Questie and other map-pin addons:** recognised by frame name only, to keep their pins out of Carbonite's dock.
- **Blizzard:** stock 3.3.5 textures and fonts are referenced by path. No Blizzard files are redistributed.

Using another addon's callbacks or reading its tables does not, by itself, establish licence compatibility in either direction. No such claim is made here.

## Development-only material (in the repository, not in the release ZIP)

The test harness (`tools/`, `tests/`) was written for this project. It simulates the parts of the 3.3.5 API and default UI the addon touches, and reproduces the *behaviour* of some Blizzard FrameXML functions (for example how `ShapeshiftBar_Update` re-anchors the first stance button), along with a few layout numbers such as frame sizes and anchor offsets. No Blizzard files are included. The fake DBM and BigWigs objects in the tests only mimic their public callback and message shapes. The test fixtures contain synthetic data only: no real accounts, characters or saved variables.

## Status of the licensing review

1. **Project licence:** all rights reserved, chosen by the maintainer. Contributions are accepted under the terms in CONTRIBUTING.md.
2. **Removed dataset:** not in the repository or in any release from 0.7.0 on. The 0.5.0–0.6.1 ZIPs are not in this repository. Anyone who shares them needs to keep DBM's attribution and CC BY-NC-SA 3.0 terms.
3. **BigWigs:** the 3.3.5 package examined (r7558) carries no licence statement. No BigWigs code is included; the addon only listens to its messages at runtime.
4. **Test harness:** see above. The maintainer may want to look it over before publishing, since it will be public.

## Release package check

Every release ZIP is built by `scripts/package.py` and checked by `scripts/check_package.py` (locally, and on GitHub before publishing). It contains only this project's files: the `.toc`, the Lua files it lists, README.md, CHANGELOG.md, PROVENANCE.md and LICENSE.txt. The check refuses:
- DBM or BigWigs module code;
- the removed encounter dataset;
- game or account files (WTF, SavedVariables) and other addons' folders;
- executables;
- versions that don't agree.
