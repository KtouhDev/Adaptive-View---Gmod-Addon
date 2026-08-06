# Changelog

## 2026-06-07

- Fixed Modern UI per-model rule edits not always being saved after dragging visual handles or changing pin-camera settings.
- Added ChloeV to the `Thank them!` credits window for reporting the Modern UI PM settings save bug.

## 2026-06-05

- Added the new Modern UI rule editor, opened from `Edit Rules` in the Q-menu.
- Added visual rule editing for camera height, crouch camera height, collision hull height, width/length bounds, camera X/Y offset, and physical attributes.
- Added model preview, model rule lists, drag-and-drop rule creation, per-model previews, metric/imperial unit display, and live value syncing between the visual editor and rule fields.
- Moved the old rule editor controls into a clearly marked `Legacy` section so existing manual workflows remain available.
- Fixed Modern UI collision-height conversion so the visual hull height now matches the in-game adaptive hull much more closely.
- Fixed NPC/NextBot collision height when using per-model rules by removing an extra server-side height padding value.
- Improved rule handling for NPCs and other adaptive entities so matching model rules are applied more consistently.
- Added clickable credits for R4YL0, mec fluuri, CokedBadger, and TOYO1515.
- Kept adaptive speed, adaptive jump, and adaptive pickup weight disabled by default while still respecting saved user/server settings.
- Updated Workshop package ignore rules so local mockups, SVG source files, and design-only assets are not packed into the `.gma`.

## 2026-05-23

- Added compatibility handling for TacMove crouch/movement behavior.
- Adaptive View now avoids fighting TacMove's movement and duck-hull logic while keeping adaptive camera height active.
- Added support for player model scale from `ulx scale` / `SetModelScale()`.
- Added `pmav_scale_support`, `pmav_scale_min`, `pmav_scale_max`, and `pmav_resync_scale`.
- Added automatic resync when a player's model scale changes.
- Prepared hidden camera FOV and camera X/Y offset settings for the future Modern UI rule editor.
- Added a Rules menu notice about the planned Modern UI update.
- Added TimRtec, mec fluuri, and Remenix to the `Thank them!` credits window.

## 2026-05-20

- Added TacMove compatibility handling: Adaptive View no longer fights TacMove's movement/duck-hull logic while keeping adaptive camera height active.
- Fixed crouch camera restoration when another movement addon rewrites `ViewOffsetDucked`.
- Fixed TacMove crouch-height prediction by using the normal GMod duck ratio instead of TacMove's taller tactical crouch offset.
- Fixed movement compatibility with addons such as Tac-move by leaving WalkSpeed/RunSpeed/JumpPower untouched when Adaptive View movement scaling is disabled.
- Fixed `Speed = 0` and `Jump force = 0` model-rule values so they truly mean `off`.
- Added per-model `Speed` and `Jump force` rule values.
- Added quick rule editor buttons: `Apply`, `Apply & Save`, and `Back to save`.
- Changed quick rule editing so temporary Apply changes do not write to the local rules file.
- Added default `speed = -1` and `jump = -1` values to normalized model rules for old and new configs.
- Increased the automatic minimum movement speed scale for small models.
- Reworked adaptive jump scaling so tiny models no longer get extremely weak jumps.
- Added soft landing handling for small models using adaptive jump scaling.
- Added a short NPC/NextBot damage-bounds grace period after spawn/apply to prevent Lambda Players from briefly taking no or incorrect bullet damage.
- Added KarmotineOverdose to the `Thank them!` credits window for the movement slider idea.
- Added multiplayer permission hardening for Adaptive View settings.
- Added `pmav_alladmins` to optionally allow non-admin players to edit settings.
- Added `pmav_injail` to lock the settings menu for everyone, including admins.
- Restricted non-admin Q-menu access to the `Thank them!` credits button unless server settings allow editing.
- Blocked client-side settings net messages from unauthorized players on the server.
- Disabled debug bounds in multiplayer and stopped debug bounds networking outside singleplayer.
- Updated debug behavior so `pmav_injail` also blocks debug rendering in singleplayer.
- Added a stuck watchdog that can move players out of solid geometry after adaptive hull changes.
- Improved stuck checks so non-solid/passable props are ignored.
- Started planning the multiplayer server-side config/rules model for per-server model rules.
- Added a compatibility note for planned VR support and future VR-specific camera/collision handling.

## 2026-05-19

- Renamed the main Q-menu toggle to `Enable add-on`; disabling it now stops the add-on logic and restores player state.
- Expanded per-model rules with separate camera height, camera offset, hitbox height, hitbox width, and hitbox length controls.
- Kept the rule editor open after saving so values can be tuned live.
- Added auto collision aspect locking for generated width/length values.
- Fixed `Hitbox height = 0` so it means automatic collision height instead of inheriting camera rule height.
- Improved player auto collision sizing by using body/bone-based width estimates instead of raw model bounds where possible.
- Added optional walk/run speed scaling and jump-power scaling from adaptive hitbox height.
- Added `Thank them!` credits window with clickable Steam profile links.
- Improved reload behavior so players and existing adaptive entities are recalculated after script/settings reloads.
- Continued NPC/NextBot/Lambda/Zeta collision handling improvements without enabling constant live recalculation.

## 2026-05-18

- Updated adaptive collision handling for players, bots, NPCs, and NextBots.
- Added `pmav_npc_collision` / Q-menu option for NPC and NextBot collision adaptation.
- Added `pmav_collision_only_players` / Q-menu option for player-only collision mode.
- Improved debug bounds rendering so player crouch/stand hulls display separately.
- Reduced live-style collision recalculation; NPC/NextBot bounds now apply on spawn/settings changes instead of continuous updates.
- Added protections against external collision-bound overrides on managed adaptive entities.
- Added damage filtering for NPC/NextBot legacy invisible hitboxes outside Adaptive View bounds.
- Updated Workshop package ignore rules for `.gma` and Markdown files.

## 2026-05-16

- Added README and project documentation.
- Documented Workshop attribution expectations for forks.

## Workshop Release

- Adaptive camera height for unusual player models.
- Real view offset support for aligned aiming, bullets, traces, and physgun direction.
- Optional adaptive collision modes.
- Per-model rules with manual height, offset, auto mode, and disable mode.
- Multiplayer-safe behavior.
- NPC and NextBot collision bounds support.
- Q-menu settings under `Options > Player > Adaptive View`.
