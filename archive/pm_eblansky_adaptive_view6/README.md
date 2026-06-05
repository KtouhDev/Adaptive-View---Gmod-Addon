# Adaptive View

Adaptive View, also known internally as `pm_eblansky_adaptive_view` or **AView**, is a Garry's Mod addon that adapts the player's camera height, aiming origin, and optional collision bounds to better match the current player model.

It is made for custom player models that are much shorter, taller, wider, or stranger than the default GMod player hull.

## Workshop

Steam Workshop page:

https://steamcommunity.com/sharedfiles/filedetails/?id=3726733215

## Features

- Automatically adapts first-person camera height to the current player model.
- Uses real player view offsets, so aiming, traces, bullets, and physgun direction follow the corrected camera height.
- Optional adaptive player collision modes.
- Per-model rules for exact height, offset, auto height, or disabling the addon for specific models.
- NPC and NextBot collision bounds support for small or unusual models.
- Multiplayer-safe behavior to reduce prediction issues and prevent tiny player hull abuse.
- Q-menu configuration without leaving the server.
- SWEP-friendly design: does not override SWEP `CalcView` or viewmodel hooks.

## Q-menu

Settings are available in:

```text
Options > Player > Adaptive View
```

From there you can:

- Enable or disable Adaptive View.
- Select collision adaptation mode.
- Adjust global camera offset.
- Set min/max automatic camera height.
- Add, remove, and edit per-model rules.
- Manually edit model offsets and exact heights.
- Disable the addon for broken or incompatible models.

## Collision Modes

Adaptive View can change collision behavior depending on what you need:

- `Nothing` - do not touch collision.
- `Height only` - adapt only hull height.
- `Width/length only` - adapt horizontal hull size.
- `Height + width/length` - adapt the whole collision hull.

For multiplayer, the addon keeps safer behavior enabled by default to avoid tiny player models abusing very small collision bounds.

## Per-Model Rules

Some player models have broken attachments, unusual bones, or weird proportions. For those cases, AView lets you create model-specific rules:

- `Auto height`
- `Exact height`
- `Disable for this model`
- Custom model offset

Double-click a rule in the list to edit it. Right-click a rule to remove it or copy the model path.

Rules are stored client-side in:

```text
data/pm_eblansky_adaptive_view/models.json
```

## Installation

### Workshop

Subscribe on Steam Workshop:

https://steamcommunity.com/sharedfiles/filedetails/?id=3726733215

### Manual

Place the addon folder in:

```text
garrysmod/addons/pm_eblansky_adaptive_view
```

The folder should contain:

```text
addon.json
lua/autorun/pm_eblansky_adaptive_view.lua
lua/autorun/client/pm_eblansky_adaptive_view.lua
```

## Development Reload Commands

When editing locally, you can reload without restarting GMod:

```text
lua_openscript autorun/pm_eblansky_adaptive_view.lua
lua_openscript_cl autorun/client/pm_eblansky_adaptive_view.lua
```

## Packaging

Example packaging command:

```powershell
gmad.exe create -folder "path/tp/pm_eblansky_adaptive_view" -out "adaptive_view.gma"
```

Example Workshop update command:

```powershell
gmpublish.exe update -addon "adaptive_view.gma" -id "3726733215" -changes "Update notes here."
```

## Compatibility Notes

Adaptive View is designed to avoid common conflicts:

- It does not override SWEP `CalcView`.
- It does not override viewmodel hooks.
- It uses real player `SetViewOffset`, `SetHull`, and `SetHullDuck`.
- It uses stable setters to avoid repeatedly applying the same hull/view offset values.

Possible conflict cases:

- Addons that constantly override player view offset.
- Addons that constantly override player hull size.
- Gamemodes with custom collision systems.
- NPC or NextBot bases with custom hitbox, damage, or collision logic.
- Models with broken attachments or unusual bones.

NPC and NextBot support is best-effort. Lua can adjust collision bounds, but it cannot reliably rewrite every model's internal `.mdl` hitboxes or custom damage logic.

## Reporting Issues

When reporting a bug, please include:

- The model path.
- Whether it happens in singleplayer or multiplayer.
- Your selected collision mode.
- Any camera, legs, SWEP, NPC, or NextBot addons involved.
- Console errors, if any.
- Screenshots or a short clip if the issue is visual.

## Source Code

Source code is available on GitHub:

```text
TODO: add GitHub repository URL
```

## License and Attribution

This project is licensed under the MIT License.

You may fork, modify, and redistribute the source according to the MIT License.

However, if you upload a fork, modified version, or derivative of **Adaptive View / AView / pm_eblansky_adaptive_view** to the Steam Workshop, you must clearly credit the original addon and include a link to either:

- the original Steam Workshop page, or
- the original GitHub repository.

Please do not upload Workshop forks in a way that hides the original authorship.

## Internal Name

The public addon name is:

```text
Adaptive View
```

The internal name remains:

```text
pm_eblansky_adaptive_view
```

This is kept for saved settings compatibility, hook IDs, data paths, and a little bit of history.
