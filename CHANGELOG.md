# Changelog

Entries before 0.7.0 describe the addon as it was at the time. The built-in encounter timings described in 0.5.0–0.6.1 (extracted from DBM-Warmane's boss modules) were removed in 0.7.0 and are not part of any later release.

## 0.7.0: Optional boss mods, independent learning, stance badge fix

**Boss mods are optional**
- Deadly Boss Mods and BigWigs are optional. With either one (or both), their live timers show as before. With neither, the timeline shows what your account has validated for that boss on your server, plus the boss's casts as they happen.
- When DBM and BigWigs both time the same ability, only one entry is shown. It is DBM's by default; there is a new option to prefer BigWigs. Abilities are matched by spell ID, not by name. A difficulty variant (another ID with the same name *and* icon) counts as the same ability. Generic bars such as phases and adds are matched only to each other.
- A BigWigs engage message no longer starts a fight by itself. DBM trash modules and custom pull timers are ignored.

**Built-in encounter data removed**
- The DBM-derived dataset (`TimelineData.lua`, 464 bosses) and the tool that built it are gone. The list of known bosses, the openers, cooldowns, enrage timers and "important/dangerous" spell lists that came from it are gone too.
- Bosses are recognised by boss frames, world-boss classification, DBM's active encounter module, or your confirmation. Your confirmation is remembered per server and instance and can be undone.
- On an unfamiliar boss with no boss mod, the timeline says **Learning** and invents nothing.

**Learning**
- Validation no longer compares against built-in timings. A timing is accepted on its own accuracy and coverage on held-out casts from 2+ later pulls. Boss mod timings are compared against real casts only to decide which source to show, and are never samples.
- Intervals after an interrupted cast, and gaps long enough to hide a skipped or missed cast, are no longer samples.
- Spells a boss casts every few seconds are remembered as filler and not shown.
- Health-trigger estimates show "waiting" instead of a countdown when the boss isn't losing health, is being healed, or the estimate is more than 5 minutes away or unstable.
- While a boss is casting an ability, that cast replaces the ability's own countdown.
- Unfamiliar casts are shown but no longer set off the critical warning. The warning is for known mechanics.

**Migration from 0.6.x** (automatic, runs once)
- A copy of the old boss knowledge is kept once in `BlizzUIRebornDB.timeline.timelineBackup`.
- Observed intervals, openers, thresholds, manual settings, flags and boss confirmations are kept. Old confirmations are marked "legacy".
- Validation scores that depended on the removed data are cleared.
- Accepted timings are kept but labelled "re-checking" until 3 newly observed casts confirm them. If those casts disagree, the timing goes back to validation.
- "Use Built-in / Boss Mod Timing" becomes "Always Use Boss Mod Timing".
- Layouts and settings are untouched.

**Sharing**
- Shared boss data (BRK3) contains validated timings only. It has no raw samples, boss mod data, or unvalidated imports.
- Imports are size- and schema-checked data, never code, and 0.6 strings still import.

**Stance badge**
- The badge was a child of the player frame at the default level, so it was drawn under the frame's portrait, level and border art, which are drawn by nested child frames. It now sits one level above that art, in the player frame's own strata.
- The ring texture is cropped to its visible circle, removing the transparent padding that pushed it off-centre.
- It is placed by mirroring the level circle across the portrait, measured from the live frames. It keeps following the player frame when it is moved, scaled, when layouts change and after reloads. It is still click-through.

**Not verified in the game client:** see "Testing" in the README.

## 0.6.1: Stance bar, Carbonite icons, stance badge

- **Stance Bar now moves and resizes** for every class that has one (paladin auras, warrior stances, death knight presences, druid forms, rogue stealth, shadowform). Before, Blizzard put the first button back every time the forms updated (including in combat), so the bar never stayed where you put it. It now works like the Totem Bar: the whole Blizzard bar sits in the layout holder and is taken out of Blizzard's frame positioning. Horizontal or vertical, size and padding all work. It is in the basic Edit Mode list for those classes. Classic still gives the original bar back.
- **Carbonite status icons can go anywhere around the map.** Drag them and they attach to the nearest side of the Carbonite window: a column on the right or left, or a row above or below (below goes under the clock). You can slide them anywhere along that side. There is also a "Side of Map" setting. Reset To Default Position puts them back in the Retail column on the right.
- **New stance badge** next to the player level. It is a round badge with the stock gold ring, mirroring the level circle on the other side of the portrait. It shows your current warrior stance, death knight presence or paladin seal, and hides when none is active, in a vehicle, and for other classes. It never blocks clicks on the player frame. Turn it off with "Show Stance Badge" in the Player Frame's Edit Mode settings.

## 0.6.0: Boss Timeline correctness and adaptive encounter knowledge

**Fixes from the 0.5.2 review** (each has a replay test):
1. **Phase and difficulty conditions.** The built-in data no longer contains timers that DBM only starts in certain phases or difficulties; flat tuples can't represent them (Mimiron's Phase 2/3/4 all fired at once off one trigger). Openers that differ by difficulty are kept as a time window. Phase changes (from DBM's stage messages) cancel this addon's obsolete predictions.
2. **Boss mod ownership.** Once DBM or BigWigs times an ability, a cancelled boss mod timer never brings back an older built-in or learned estimate (or its warning). The addon's own estimate returns only after the boss is seen casting it and the boss mod doesn't restart its timer.
3. **Boss-only, for real.**
   - Only the fight's own bosses (and the creatures of its boss mod module) drive predictions. Trash casting a same-named spell is ignored.
   - DBM and BigWigs timers, kills and wipes are only taken from the fight's own module; trash modules and other bosses' modules are ignored.
   - Bosses from another encounter (Putricide on his balcony during Rotface) don't join the fight.
   - With a boss mod attached, the fight ends on its kill message rather than the first boss death (Northrend Beasts).
4. **Interrupts.** An interrupted cast disappears at once, even when the boss isn't your target or focus, and is not learned as a cast.
5. **Learning is kept per realm, dungeon/raid and difficulty (10/25, normal/heroic), per boss and spell ID, and per phase when phases are known.** Time spent in other phases is not counted as a cooldown. Timings stored by 0.5.x had none of this, so they are dropped on upgrade; which creatures are bosses and which spells are dangerous is kept.
6. **Layouts.**
   - Characters that never picked a layout keep following the account default, even after it changes.
   - The layout menu has **Use Account Default** to go back to following it.
   - Deleting the default doesn't turn a following character into a "chosen" one.

**Adaptive encounter knowledge** (account-wide, all characters on this PC's account):
- **Evidence.** Only real boss casts count. Boss mod timers, the addon's own predictions and practice fights never do. The start and success of one cast count once; interrupted attempts don't count; hits on several players count once.
- **From learning to trusted.** A new ability gets a *provisional* estimate after three consistent intervals in one pull, labelled "learning". To become a trusted server timing it needs:
  - 5+ intervals over 3+ pulls;
  - then to beat the built-in timing (and any timing already trusted) on 3+ later casts it wasn't fitted on.
  
  Timings with legitimate variation become a **window** ("in 20-28s"). Unstructured variation gets no timing claim.
- **Re-checking and rollback.**
  - A trusted timing that keeps missing is re-checked, and the previous one is kept for rollback.
  - **Server Changed...** (in Encounter Details) re-checks everything without throwing it away. A new timing only replaces the old one once validated, so it doesn't flip-flop.
- **Learned vs boss mod.**
  - Both are measured against the real casts on this server.
  - When a learned timing proves clearly more accurate than DBM/BigWigs (for example DBM says 30s, the server does 24s), the learned one is shown.
  - Interface options let you always use the boss mod, or prefer learned timings.
- **HP thresholds.**
  - An ability that happens at a boss health percentage is learned as that percentage, never as the fight time it happened to take. This needs 3 pulls where the health was stable but the time varied. A cast delayed below the threshold doesn't move it. If both health and time were stable, it's marked ambiguous and not claimed.
  - In the fight, the ETA comes from the boss's measured health loss: recent and longer trends, so healing and absorbs count and jumps reset the trend. It shows as a range when those trends disagree.
  - When damage stops it says "waiting", with no infinite countdown. At the threshold it says "reached, waiting for the ability": never "cast now".
  - One warning per occurrence, even if the ETA bounces around 5 seconds.
- **Controls.**
  - Right-click any ability (or use `/br timeline details`) to:
    - hide it, or always show it;
    - set your own repeat time or HP threshold;
    - lock the learned timing;
    - use the previous timing, or the built-in/boss mod one;
    - forget it.
  - The **Encounter Details** window lists what's known about the last boss, with the same controls. It can also **share or import** boss knowledge as a data-only string. Imported timings are only used once your own fights confirm them.
- **Custom bosses.** Detected from boss frames and world-boss flags. Target one and type `/br timeline boss` to confirm it. "??" level elites are no longer assumed to be bosses.
- **Options** (Interface > AddOns): Show predicted abilities (off = only boss mod timers and live casts), Keep learning while both displays are hidden (off by default: with both displays off nothing is collected), and the boss mod/learned preference.

**Display:**
- "~" marks estimates; boss mod timers and cast bars are shown as they are.
- The tooltip (and a small label in the Bars view) says where each timing comes from: built-in, learned, learning, re-checking, manual, DBM, BigWigs, live, HP.
- "+N" shows how many abilities didn't fit. With spell names shown, names never overlap and never run off the track.
- A prediction reaching zero says "soon", never that the boss cast it.
- The display list is only rebuilt when something changes.

**Limits:** without DBM there's no phase signal, so learned timings of phase-changing bosses may be windows or withheld. Encounter-script branches a boss mod never announces can't be inferred. Knowledge lives in this account's saved variables on this PC (no syncing), and the game writes it at logout or /reload.

## 0.5.2

- **Import / Share windows work again.** The 3.3.5 client caps how high a window can be layered. These windows were set above that cap, so their text box and buttons were drawn and clicked *underneath* the window itself: you couldn't paste or copy. All windows now use safe layers, and every part of a window is kept above the window.
- **Your layout on every character, as on Retail.**
  - Layouts are account-wide unless you tick "Character Specific".
  - The first account-wide layout you use becomes the **default for all characters**. New characters, and alts that never picked a layout themselves, start on it.
  - Change the default from the layout's gear menu: **Default for All Characters**. It's marked "(Default)" in the list.
  - A character-only layout can be shared from its gear menu: **Make Account-Wide**.
  - An alt that picked its own layout keeps it.

## 0.5.1: Boss Timeline shows mechanics only

Like Retail, the timeline now shows only the mechanics you have to deal with, not every spell a boss casts.
- **Shown:** abilities with a built-in or boss-mod timer, and the spells DBM announces or warns about for that boss (built in for all 464 bosses).
- **Also shown, learned from your fights:**
  - **Dangerous** hits: 35% or more of a player's health, or a kill.
  - Spells that hit **3 or more players** at once.
  - **Adds** being summoned.
- **Dangerous** abilities (big hits, DBM "run/move/interrupt" warnings) get a **red ring** and a "Dangerous" line in the tooltip. Example: Skarvald's big hit in Utgarde Keep is marked dangerous, and Dalronn's Shadow Bolts are ignored.
- **Filtered out:** filler such as Shadow Bolts at the tank, including their casts in progress and warnings.
- **Show every boss ability** (Interface > AddOns > BlizzUI Reborn) brings everything back if you want it.
- At most the 8 soonest abilities are drawn on the timeline.

## 0.5.0: Boss Timeline

A 3.3.5 version of Retail's (Midnight) Boss Abilities timeline and Boss Warnings. In a boss fight it shows the boss's next abilities and a countdown to each one, and warns you when one is about to happen or the boss starts casting it.

**Timeline view** (Retail's default): a track with the "now" end at the bottom. Ability icons travel toward it: the 0–5 second section is widest, then 5–15 and 15–40 seconds. Abilities further away wait in a short queue at the far end.
- Each icon shows its countdown.
- A diamond marks 5 seconds. Inside 5 seconds the icon lights up.
- A cast in progress pulses with a red countdown until it goes off.
- If a predicted ability runs late, it waits at the now end until it happens (or drops off after its usual variation).
- Hover an icon for the spell tooltip.

**Bars view:** one bar per ability, soonest at the bottom, with the icon, name and time.

**Boss Warnings:** big text at the top of the screen.
- **Medium** (gold): "Bone Storm in 5".
- **Critical** (red): "Lord Marrowgar: Bone Storm", with the raid-warning sound.
- Frequent abilities stay on the timeline only, so this never spams.

Bosses only. A fight starts for boss units, known boss creatures, world bosses and "??"-level elites inside instances. Trash and normal mobs never start it.

How the next ability and its timing are worked out, best source first:
1. **Deadly Boss Mods or BigWigs timers**, if installed. They follow phases, but they are still estimates for this server (see 0.6.0). Tested against DBM-Warmane's and the 3.3.5 BigWigs' events. When a boss mod has a timer for an ability, the addon's own guess for it is hidden, so nothing shows twice.
2. *(Removed in 0.7.0.)* **Built-in timings** for 464 bosses: every 3.3.5 raid (Naxxramas to Ruby Sanctum, including realm-specific enrage timers such as Frostmourne's), WotLK dungeons, and older raids. Compiled from the DBM-Warmane boss modules' data (Deadly Boss Mods, deadlybossmods.com, CC BY-NC-SA 3.0).
3. **Learned timings.** The addon records when each boss uses each ability. Once the intervals are consistent, the learned timings are used instead of the built-in ones, so the predictions match your server. Bosses with no data at all (custom or world bosses) show "Learning this fight..." and get predictions after a few casts. Everything learned is kept between sessions.
4. **Casts in progress.** From a boss's cast bar the timing is exact. From the combat log it is estimated from the spell's cast time.

**Edit Mode:** two new elements, **Boss Timeline** and **Boss Warnings**, in the Combat list. Untick either one to turn it off. Both show a moving preview while Edit Mode is open, and can be dragged, nudged, reset, saved in layouts and shared like any other frame.
- **Boss Timeline settings** (Retail's list and ranges): View (Timeline/Bars), Orientation, Icon Direction, Icon Size 50–200%, Overall Size 50–200%, Padding and Bar Width (Bars view), Background, Transparency, Visibility (Always/In Encounter), Tooltips (None/HUD/Cursor), Flip Horizontally, Show Spell Name, Show Timer.
- **Boss Warnings settings:** Size, Icon Size, Transparency, Show (All/Critical Only), Play Sound.
- **Positions:** the Modern preset puts the timeline in Retail's spot, left of the action bars, and the warnings at the top centre.

**Interface > AddOns > BlizzUI Reborn:** Use DBM/BigWigs timers, Learn timings, Hide Long Countdowns, Hide Queued Countdowns, a **Practice Fight** button (a 40-second demo through the real engine, also `/br timeline test`) and Forget Learned Timings (`/br timeline reset`).

Performance: while you are not fighting a boss nothing runs, and the combat log isn't even listened to out of combat. In the test, 20,000 combat-log events took about 0.05 s of CPU.

Honest limits: 3.3.5 has no encounter data from Blizzard, so without a boss mod the predictions are the built-in and learned timings. They can be a few seconds off, and at phase changes they adjust once the boss casts again. With DBM or BigWigs installed, the timeline is as accurate as those addons.

## 0.4.2

Carbonite minimap icons, laid out as in the reference picture:
- The status icons (calendar, mail, queue eye, tracking...) are now placed around **Carbonite's map window** itself: a column down the window's right side, starting level with its title bar. The Addon Compartment sits under the window's lower-left corner and the clock is centred under the window. Clicking the compartment opens its list beside the window.
- 0.4.1 placed them around the minimap Carbonite embeds *inside* its map. That minimap follows your character around the map and fades out when you hover the map, so the icons chased it while flying, the clock ended up inside the map, and hovering the map made everything jump back and forth (the flickering). Nothing is placed inside the Carbonite window any more, and the icons only move when you move or resize the window.
- Carbonite's dock only hands back map pins it can recognise by name (Questie, HandyNotes, GatherMate, TomTom...); nothing else in the dock is touched.

## 0.4.1

- **Always Show Buttons off now really hides empty slots.** Empty action slots are blank, like Retail, even when the game's own "Always Show ActionBars" option or bar art would show them. Picking up a spell still shows every slot so you can drop it anywhere, and slots that empty in combat (stance or page changes) go blank too. The bar art itself (Action Bar 1's stock texture) is unchanged unless you tick Hide Bar Art.
- **Carbonite: the grid of mail icons is gone.** Those were map pins (Questie town icons such as mailboxes, and similar pins from HandyNotes, GatherMate, TomTom...). Carbonite's "Move Minimap buttons into Carbonite button window" option was swallowing them into its button dock as if they were addon buttons. Pins are now kept out of the dock, and any it already took go back to the minimap. Your real mail icon is the single envelope in the icon column.
- Retail minimap arrangement with Carbonite (replaced in 0.4.2).
- **New element: Totem Timers.** The totem timer icons under the player frame (shaman totems, death knight ghoul) can be moved and resized in Edit Mode (Frames category). This is separate from the Totem Bar, which holds the totem buttons.

## 0.4.0

Carbonite minimap:
- When Carbonite embeds the minimap in its map window, the status icons, Addon Compartment and clock now line up in one column beside that minimap square, on the side facing away from the map. Before, the compartment covered the minimap, the clock sat under the middle of the whole Carbonite window, and the other icons were placed around the window instead of the minimap.
- Stray addon minimap buttons, including those in Carbonite's dock, are collected into the Addon Compartment. This can be turned off in Interface > AddOns > BlizzUI Reborn. Map pins (gathering nodes, quest markers) are never touched.

Checked against the real 3.3.5 interface code:
- Buffs: Blizzard hangs the buff and weapon-enchant frames off `ConsolidatedBuffs` on every aura update, and the old element anchored them the other way round, which makes an anchor loop (Lua errors). The element now moves `ConsolidatedBuffs`. Saved positions are converted automatically.
- Action Bar 5 only exists while Action Bar 4 is on in 3.3.5. Ticking Bar 5 now turns on Bar 4 too, and turning off Bar 4 turns off Bar 5.
- "Always Show Buttons" no longer writes the buttons' `showgrid` attribute, which could cause "action blocked" errors when stances or pages changed in combat. It now draws the stock empty-slot art under the bar instead.
- The bar toggles are saved with the correct Blizzard variable. Before, Blizzard's "Always Show ActionBars" option could be reset by mistake.
- No fields are written on Blizzard frames any more (secure code reading them could spread taint). Frames managed by Blizzard's frame manager, now including the chat frame, are taken out of its list while in a layout.
- Player, target and focus frames are no longer marked user-placed (3.3.5 never repositions them), so the client's layout cache can't store moved positions.
- The drift check also catches Blizzard adding a second anchor without clearing the first.
- Boss frames were removed from Edit Mode. 3.3.5's secure frame manager re-anchors them on every update, and they only appear in combat, when addons can't move them back.
- Totem bar: finishes hiding correctly when the totem bar is taken away.

New, matching Retail's Edit Mode settings:
- **Bar Visible** (Always / In Combat / Out of Combat / Hidden) for Action Bars 2–5. Key bindings keep working, like on Retail.
- Micro Menu **Order** (Default/Reverse), Bags **Direction**, **Opacity** for Buffs and the Objective Tracker, Retail setting ranges (unit frames 50–200%, chat 250–800 × 120–800, tracker height up to 1000).
- New movable elements: **HUD Tooltip** (the default tooltip position), **Durability Figure**, **Vehicle Seat Indicator**, **Timer Bars** (breath/fatigue), **Raid Warnings**.
- **Bagnon currencies:** Blizzard only shows "Show on Backpack" currencies on its own backpack window. With Bagnon they now appear in a strip under Bagnon's bags (can be turned off in the settings).

## 0.3.3

- Totem bar: switching between Call of the Elements, Ancestors and Spirits works again after the bar has been moved. The bar's slide-in animation kept dragging it back to Blizzard's default spot on every page switch (and in combat it could stay stuck there). The moved bar now sits in its own holder with the animation paused, the same approach Bartender4 uses.

## 0.3.2

- Moved action bars (including stance and pet bars) now use the LOW frame layer, so windows such as Carbonite's quest log and the character panels draw on top of them.
- The action bar page arrows have their own Edit Mode entry, **Action Bar Page Arrows**. Untick it to hide them, or drag and resize them. They are hidden in Modern. Layouts that used the old "Hide Bar Scrolling" option are converted automatically.

## What's new / fixed

| Reported problem | What changed |
|---|---|
| Switching layouts did nothing | New layout engine. Switching applies every frame immediately. Frames missing from a layout go back to their Blizzard position. You're prompted to save or discard unsaved changes. |
| Creating a named layout did nothing | New Layout, Rename, Copy, Delete, Import and Share all work from the layout dropdown (gear icon on each layout). Names are checked, and layouts can be account-wide or character-specific. |
| Exiting Edit Mode did nothing | The close button, Escape and combat all exit reliably. With unsaved changes you get Save and Exit / Exit / Cancel. On a preset, Save and Exit asks for a layout name. |
| Some frames couldn't be moved (Target Frame) | Every frame, including hidden ones (target, focus, party, boss, pet bar), has a selection box you can drag. Dragging is smooth (every frame, not 20 times a second), with snapping, and arrow keys nudge (Shift = 10). |
| Revert All Changes often didn't work | Revert now restores the saved layout exactly (tested over repeated random edits). The client's layout cache no longer overwrites "original" positions between sessions. |
| Modern didn't change everything | Modern now positions every frame in the TWW default arrangement (bars stacked bottom-centre, player/target above them, cast bar between, buffs by the minimap, micro menu and bags bottom-right) and hides the gryphons and bar art. Frames keep the game's own art and colours. |
| Laggy | The old build re-applied every frame 20 times a second and on every frame-manager call. Now nothing runs while idle. Only frames that Blizzard actually moved are re-applied. |

Also new:

- **Quick Keybind Mode** (Edit Mode button, action-bar settings, or `/br keybind`): hover a button and press a key.
- Edit Mode uses its own dropdown menus instead of Blizzard's (Blizzard's cause taint on 3.3.5), styled like the original build.
- Action bars 2–5 can be turned on/off from the Edit Mode list, like Retail.
- Positions are anchored to the nearest screen edge, like Retail, so layouts survive resolution and UI-scale changes.
- Stance/form bars (warrior, druid, rogue, shadow priest) follow Action Bar 1.

