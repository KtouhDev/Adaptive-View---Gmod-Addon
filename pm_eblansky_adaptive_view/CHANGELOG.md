# Changelog

## 2026-05-20

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
