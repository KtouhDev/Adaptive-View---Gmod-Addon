# Changelog

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
