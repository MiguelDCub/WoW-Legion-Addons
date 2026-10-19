# TrinketTracker

Version **1.2.1** for **WoW Legion 7.3.5**, interface `70300`.

Movable visual tracker for equipped trinkets (slots 13 and 14), supported buffs, stacks, item cooldowns and known internal cooldowns. Never equips or activates items.

## Installation

Copy this folder into `Interface/AddOns/TrinketTracker/` and enable the addon. Settings are saved per character in `TrinketTrackerDB`.

## Commands

Use `/ttracker` or `/trinkettracker`:

- `unlock` / `lock`: move icons by left dragging out of combat, or lock them.
- `reset`: reset positions and scales.
- `scale 1.2`: scale both icons; `scale 13 1.2` scales one slot (13 or 14). Range: 0.5 to 3.
- `test`: toggle a 10-second visual preview.
- `status`: show equipped items and mappings.
- `debug`: toggle buff diagnostics.
- `auras`: list player buffs and spell IDs.
- `database` or `db`: show built-in mappings.
- `bind 13 127923 proc 55`: override the equipped item's effect using slot, spell ID, kind (`use`, `proc`, `passive`) and optional ICD in seconds.
- `unbind 13`: remove the equipped item's override.

## Included mappings

Moonlit Prism, Infernal Writ, Mithril Wristwatch, Wriggling Sinew, Swarming Plaguehive and Nightmare Bloom.

Unknown effects display UNKNOWN. Target damage procs display DMG PROC without an invented countdown. Internal cooldowns use the observed buff start; Infernal Writ's remaining duration is estimated from stacks.

No software license has yet been selected. Community addon; not affiliated with or endorsed by Blizzard Entertainment.
