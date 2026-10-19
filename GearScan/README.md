# GearScan

Exports equipment, bag contents, character stats, talents and artifact information for **World of Warcraft: Legion 7.3.5** (interface `70300`).

## Installation

Copy the `GearScan` folder into `Interface/AddOns/` and enable the addon.

## Usage

1. Type `/gearscan` to capture a snapshot.
2. Type `/reload` to save it to disk.
3. Find the exported data in:

   `WTF/Account/<account>/SavedVariables/GearScan.lua`

The export contains the latest snapshot in `GearScanDB.latest`.

### Artifact traits

Open the artifact trait tree at the Artifact Forge, then run:

```text
/gearscan artifact
/gearscan
/reload
```

Artifact information is cached for later scans.

## Commands

`/gs` can also be used instead of `/gearscan`.

| Command | Description |
| --- | --- |
| `/gearscan` | Capture equipment, bags, stats, talents and artifact information. |
| `/gearscan status` | Show information about the latest snapshot. |
| `/gearscan artifact` | Cache available artifact traits. |
| `/gearscan clear` | Clear the latest snapshot while keeping the artifact cache. |
| `/gearscan clearartifact` | Clear the artifact cache. |

## Exported data

- Equipped items and equippable items in bags.
- All bag contents.
- Character stats and specialization.
- Selected talents.
- Artifact weapon, relics and available traits.

Each scan replaces the latest snapshot. Copy the exported file elsewhere to keep previous scans.
