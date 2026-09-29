# BlizzUI Reborn

[![CI](https://github.com/McDaddyYuki/BlizzUI-Reborn/actions/workflows/ci.yml/badge.svg)](https://github.com/McDaddyYuki/BlizzUI-Reborn/actions/workflows/ci.yml)

An addon for World of Warcraft: Wrath of the Lich King 3.3.5a, bringing Retail (The War Within / Midnight) style HUD Edit Mode, layouts and a Boss Timeline to the client using the game's own frames and art.

## Client and compatibility

- **Client:** developed for Wrath of the Lich King 3.3.5a (build 12340), interface 30300. Written against that client's API only; Retail-only APIs are not used.
- **Encounter compatibility:** boss timings are learned from your encounters instead of shipped as fixed schedules. This also accommodates custom encounter behavior, including on Whitemane's Frostmourne realm.
- **Optional addons it works alongside:** Carbonite, Bagnon, Deadly Boss Mods (3.3.5 backports with callbacks), BigWigs (3.3.5), LibDataBroker launchers. None of them is required.

## Install

1. Download **`BlizzUIReborn-<version>.zip`** from the [Releases page](https://github.com/McDaddyYuki/BlizzUI-Reborn/releases/latest). Don't use GitHub's green *Code → Download ZIP* button: that is the development source, and its folder name is wrong for the game.
2. Exit the game.
3. **Delete any old `Interface\AddOns\BlizzUIReborn` folder completely**, so no old files stay behind.
4. Extract the ZIP and copy the `BlizzUIReborn` folder from it into `Interface\AddOns\`. The path should be `Interface\AddOns\BlizzUIReborn\BlizzUIReborn.toc`.
5. Upgrading from 0.1/0.2 only: also delete `WTF\Account\<account>\<realm>\<character>\layout-local.txt` once.
6. Log in. New characters start on the **Modern** preset. Open Edit Mode with **Escape → Edit Mode** or **/br**.

Upgrading from 0.6.x keeps your layouts and settings. Boss knowledge is migrated, and a one-time copy of the old records is kept in the saved variables. See the [changelog](CHANGELOG.md).

## Boss Timeline

Retail's Boss Abilities timeline: what the boss you're fighting will do next, and when. Nothing is shipped with the addon: no boss list and no encounter timings. Everything comes from the sources below.

**Which creatures are bosses**

- Boss frames (`boss1`–`boss4`) and the game's world-boss classification.
- The active encounter module of Deadly Boss Mods (never a trash module).
- Creatures you confirm. When an elite with no boss flag (skull level, or 2+ levels above you, in a dungeon or raid) is your target in combat, a small question asks once whether it is a boss. You can also use `/br timeline boss`.
- Your answer is remembered for that encounter. It can be undone with `/br timeline notboss` or **Not a Boss…** in Encounter Details. "Not a boss" always wins.
- A BigWigs engage message is not enough on its own, because some BigWigs modules cover trash. Its bars are used once one of its creatures is a boss by one of the rules above.
- **Limits:** a dungeon boss with no boss flag isn't recognised until you confirm it once, so the first pull may be missed. Adds stay separate from bosses unless a boss frame, DBM's encounter module or you say otherwise.

**Where forecasts come from, per ability (one entry per upcoming cast)**

1. **DBM or BigWigs, if installed and enabled.**
   - Their live timers are shown as they run: start, update, pause and resume, stop, phase changes (DBM), kill and wipe.
   - Nothing of theirs is stored.
   - When both time the same ability, one entry is shown: DBM's, or BigWigs' if you prefer it in the options.
   - A cancelled boss mod timer never brings back an older local estimate. A newly observed cast can.
2. **What your account has learned from your encounters,** once it has been validated (see below). If a learned timing keeps proving more accurate than the boss mod's (for example the boss mod says 30s but the ability consistently occurs every 24s), the learned one is shown instead. The boss mod's timing is still used for comparison only.
3. **Health triggers.** A mechanic learned to happen at a boss health percentage gets a live estimate from that boss's own health loss.
4. **Casts in progress,** from the boss's cast bar or the combat log.

**First pull on an unfamiliar boss:** the timeline says **Learning** and shows the boss's casts as they happen. No first ability or first-cast time is invented. Predictions start once real casts have been seen and checked.

**How learning works**

- Only the bosses' own casts seen in the combat log (and their health) are used as evidence. Boss mod timers, this addon's own predictions and practice fights never are.
- Records are kept per server, instance type, difficulty (10/25, heroic), creature and spell ID.
- Interrupted casts, gaps that hide a missed or skipped cast, phase downtime and late joins are not used as cooldown samples.
- A timing is used only after it:
  - appeared in 5+ intervals over 3+ pulls;
  - then predicted 3+ later casts from 2+ later pulls it was not fitted on;
  - was on average within 15% (at least 1.5s) of those casts, with 75%+ of them within that tolerance;
  - was better than the timing already trusted, if any.

  It works the same with no boss mod installed.
- **Kinds of timing:**
  - Varying timings become a time window.
  - Random ones get no timing.
  - Health-triggered mechanics are learned as a percentage only when pulls with different pacing agree.
  - Anything ambiguous stays unclaimed.
- **Where it is kept:** account-wide means every character of this account on this computer, in the saved variables (`BlizzUIRebornDB`), kept separate from layouts. It does not sync between computers. The game saves it at logout or `/reload`.
- **Your controls:**
  - Right-click an ability or open **Encounter Details** (`/br timeline details`) to hide it, pin it, set a repeat time or HP threshold by hand, lock it, go back to the previous timing, always use the boss mod's timing, or forget it.
  - **Server Changed…** re-checks learned timings when encounter behavior changes.
  - **Share Boss Data / Import** exchanges validated timings as a plain data string. Imported timings must validate on your own fights before they're used.

**Options** (Interface → AddOns → BlizzUI Reborn) include:
- use DBM/BigWigs timers;
- prefer BigWigs when both time an ability;
- learn from your fights;
- show predicted abilities;
- keep learning while both displays are hidden (otherwise nothing is watched while they're off);
- show every boss ability;
- hide long or queued countdowns;
- which source wins when a boss mod and a learned timing disagree;
- Practice Fight;
- Forget Learned Timings.

Hiding the timeline and warnings in Edit Mode stops the display. Learning continues only if that option is on.

## Edit Mode

- **Layout dropdown:** presets (Modern, Classic), your layouts, New Layout, Import, Share. The gear icon (or right-click) on a layout gives Rename / Copy / Share / Delete.
- **Show Grid / grid spacing, Enable Snap, Advanced Options.** Advanced shows every frame. Hold Shift while dragging to skip snapping.
- **Frame list:** unchecking hides that frame's selection box. For Action Bars 2–5 it turns the bar off.
- **Clicking a frame** opens its settings: size, bar rows/icons/padding/orientation, cast bar lock/time, chat size, tracker height, XP/rep bar size, minimap size/rotation. It also has Revert Changes, Reset To Default Position and Quick Keybind.
- **Revert Changes / Save** at the bottom. Presets can't be overwritten, so Save on a preset asks for a new name.

Editable: Boss Timeline, Boss Warnings, Player, Target, Focus, Pet, Target of Target, Target of Focus, Party Frames, Totem Timers, Action Bars 1–5, the page arrows, Stance, Pet, Possess and Totem bars, Cast Bar, Buffs and Debuffs, Timer Bars, Raid Warnings, Minimap, Objective Tracker, Chat, Experience & Reputation Bars, Micro Menu, Bags, Durability Figure, Vehicle Seat Indicator, HUD Tooltip and the Addon Compartment. With Carbonite, the minimap status icons are also editable.

## Commands

`/br` Edit Mode · `/br keybind` Quick Keybind · `/br timeline test` practice Boss Timeline · `/br timeline details` Encounter Details · `/br timeline boss` / `/br timeline notboss` mark your target as a boss or not · `/br timeline reset` forget learned timings · `/br options` settings · `/br restore` put the original UI back and pause the addon · `/br enable` resume · `/br report` copyable diagnostics (include this with bug reports) · `/br resetwindows` reset Edit Mode window positions

## Carbonite

Carbonite keeps full ownership of its map and the native minimap. The Minimap element is disabled while Carbonite is loaded. Native status icons (calendar, mail, LFG, tracking...) are arranged in a column beside Carbonite's map window, with the clock and Addon Compartment under it, and taken out of Carbonite's dock. Minimap pins from other addons are kept out of the dock. `/br restore` gives them back.

**Boss Timeline scenarios covered:**
- no boss mod with empty knowledge, and with validated knowledge after a reload and on another character;
- DBM only, BigWigs only, and both at once (one entry per cast, cancellation, pause/resume, variable timers, stages);
- an observed ability timing that differs from the boss mod's;
- random, windowed and health-triggered mechanics;
- interrupts, skipped casts, wipes, late joins and phase changes;
- boss confirmation and "not a boss";
- migration from 0.6.1 saved variables, and malformed imports.

**Stance badge (simulated):**
- stacking above the player frame's art frame;
- the ring crop;
- geometry at several player-frame and UI scales, after moving the frame and switching layouts;
- stance, presence and seal changes; vehicle; disable and re-enable.

**Existing UI:** all earlier suites still pass: layouts, Edit Mode, action bars, Carbonite, compartment, keybinds, performance.

1. The stance badge is a full circle to the right of the level, with the icon fully visible:
   - on a warrior (switch stances), a death knight (switch presences) and a paladin (apply a seal and let it expire);
   - at UI scale 0.64 and 1.0;
   - after moving and resizing the player frame in Edit Mode, switching layouts and `/reload`.

   Clicking the portrait still targets you, and right-click still opens the menu.
2. No boss mod, a boss you haven't fought: the timeline says "Learning", shows the boss's casts, and predicts nothing on the first pull. Trash doesn't start a fight.
3. DBM only, then BigWigs only, then both: timers appear, update, pause, stop and follow phases. There is one entry per ability, and nothing lingers after a kill or wipe.
4. A dungeon boss without a boss flag: the "Is … a boss?" question appears once. **Track as Boss** starts tracking. **Not a Boss…** in Encounter Details undoes it.
5. After several pulls of the same boss, Encounter Details shows learned timings, and they're predicted on the next pull, also after `/reload` and on another character.
6. Carbonite: the map and minimap aren't moved or resized, zoom works, the status icons sit around the map, and launchers stay in the compartment.
7. No Lua errors (`/console scriptErrors 1`) and no "action blocked" messages in or out of combat.

## Not included yet

Retail systems with no 3.3.5 equivalent are not faked: Action Bars 6–8 (no free action slots), raid/arena frames (not in 3.3.5's default UI), Midnight's cooldown manager, damage meter and personal resource display, extra action button, loss of control, talking head. Moving boss frames is not possible on 3.3.5 (see 0.4.0). Known 3.3.5 limits: after entering or leaving a vehicle *in combat*, the player frame waits at its Blizzard spot until combat ends (Blizzard slides it there and addons may not move it back mid-combat). Frames should be moved in Edit Mode; the focus frame's own shift-drag is undone by the layout. The addon adds no textures of its own; all frames keep their 3.3.5 art.

## Reporting bugs and contributing

- Bugs and ideas: [Issues](https://github.com/McDaddyYuki/BlizzUI-Reborn/issues/new/choose) (please include `/br report`).
- Code changes: see [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests are proposals; the maintainer decides what is merged and released.
- Security problems: [SECURITY.md](SECURITY.md) (private report).

## Licence and third-party material

**All rights reserved.** See [LICENSE](LICENSE). You may install and use official releases for personal play and propose changes here, but not redistribute or reuse the code. Third-party interfaces used at runtime and the history of removed material: [PROVENANCE.md](PROVENANCE.md). Not affiliated with Blizzard Entertainment or any server or addon author.
