# LegendarySetFix

**LegendarySetFix v1.4** is an addon for **World of Warcraft: Legion 7.3.5** (interface `70300`) that helps switch between Equipment Sets containing legendary items without accidentally attempting to equip more than two at once.

Instead of relying on hardcoded item IDs, it reads saved Equipment Sets and uses WoW's native Equipment Manager to unequip conflicting legendary items before applying the target set.

## Features

- Switch by any saved Equipment Set name; no fixed list of sets or item IDs.
- Scan all regular equipment slots and respect ignored slots in the destination set.
- Unequip conflicting legendary items using the native `EquipmentManager_RunAction` API.
- Verify each item has left its equipped slot and appears in a bag before continuing.
- Finish with `C_EquipmentSet.UseEquipmentSet` and track completion.
- Queue the latest requested set while a change is still in progress.
- Diagnose planned changes without moving any items.

## Installation

1. Download or copy the `LegendarySetFix` folder from this repository.
2. Place it under `World of Warcraft/Interface/AddOns/`, so the result looks like:

   ```text
   Interface/AddOns/LegendarySetFix/
   ├── LegendarySetFix.lua
   ├── LegendarySetFix.toc
   └── README.md
   ```

3. Enable **LegendarySetFix** in the in-game AddOns list, then log in or type `/reload`.

## Usage

Create and save your Equipment Sets using WoW's built-in Equipment Manager first. Then type `/lsf ` followed by the **exact set name**:

```text
/lsf FireST
/lsf FireMPlus
/lsf FireSafe
/lsf FireTanky
```

These four names are examples, **not built into the addon**. A new set named `FireRaid`, for example, can be selected with `/lsf FireRaid` without editing the code.

You can put each command into its own WoW macro and place those macros in an **OPie** ring. Don't add a separate `/equipset` command to the same macro.

### Additional commands

| Command | Purpose |
| --- | --- |
| `/lsf <SetName>` | Apply a saved Equipment Set safely. |
| `/lsf inspect <SetName>` | Display the legendary slots that would be freed, without moving items. |
| `/lsf status` | Show active phase, queued request, native swap status and last error. |
| `/lsf debug` | Toggle detailed debug output (resets on reload). |
| `/lsf cancel` | Clear a queued request. The currently running switch continues. |
| `/lsf` | Show brief command help. |

## Requirements and limitations

- Operate **out of combat**. The addon does not bypass WoW's combat restrictions or the two-legendary limit.
- Target items must already be equipped or available in your bags; a set relying on bank items is not supported.
- Keep enough empty slots in **regular bags** to temporarily store the conflicting legendary items.
- Do not start a swap while holding an item on the mouse cursor.
- The addon may abort on inventory locks, missing items or unconfirmed swaps. If interrupted, check your equipped items and inventory before trying again; it cannot guarantee automatic rollback.
- A swap was tested successfully with the author's sets `FireST`, `FireMPlus`, `FireSafe` and `FireTanky` on a Legion-compatible client. Other configurations have not been exhaustively tested.

## Troubleshooting

If a switch fails, enable diagnostics using `/lsf debug`, then check the output of `/lsf inspect <SetName>` and `/lsf status`. Please include the exact error text, the source and destination set names, and whether the failure occurred during native unequip or the full set application.

## Version history

- **v1.4:** Native Equipment Manager unequip, with inventory confirmation before full set changes; validated across multiple legendary setups.
- **v1.3:** Attempted to release legendaries directly into bag slots (unreliable on the tested client).
- **v1.2:** Faster swaps with event-based completion and last-request queue.
- **v1.1:** Generalized slot handling.
- **v1.0:** Initial version.

## License

A software license has **not yet been selected** for this repository. The code is visible for review, but no additional reuse permissions are granted by an explicit license at this time.

*Community addon for WoW Legion 7.3.5; not affiliated with or endorsed by Blizzard Entertainment.*
