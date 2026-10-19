# RotationScan

Records combat sessions, spell casts, damage and equipment snapshots for **World of Warcraft: Legion 7.3.5** (interface `70300`).

## Confirmed support

| Class | Specialization | Scope |
| --- | --- | --- |
| Mage | Fire | Combat recording and rotation analysis, including Combustion windows, Hot Streak, Heating Up, ability charges and cooldowns. |

## Installation

Copy the `RotationScan` folder into `Interface/AddOns/` and enable the addon.

## Quick start

Start recording with an optional session label:

```text
/rs start Raid
```

When finished:

```text
/rs stop
/reload
```

Sessions are saved in:

`WTF/Account/<account>/SavedVariables/RotationScan.lua`

## Commands

`/rotationscan` can also be used instead of `/rs`.

| Command | Description |
| --- | --- |
| `/rs start [label]` | Start a recording session. |
| `/rs stop` | Stop recording. |
| `/rs status` | Show recording status and session information. |
| `/rs last` | Show the latest session summary. |
| `/rs gear` | Show selected equipment slots from the latest recorded combat. |
| `/rs mark [text]` | Add a marker during recording. |
| `/rs report` | Show session, encounter and Combustion summaries. |
| `/rs artifact` | Update artifact information from the open artifact panel. |
| `/rs mode compact` | Use compact recording. |
| `/rs mode detailed` | Include individual periodic impacts and raw cast arguments. |
| `/rs clear` | Delete saved sessions when recording is stopped. |
| `/rs help` | Show command help. |

## Recording modes

**Compact** is the default mode. It records direct impacts and groups periodic damage into one-second buckets by actor, target and spell.

**Detailed** additionally records individual periodic impacts and raw cast arguments. Use it for short tests when more detail is needed.

Choose the mode before starting a session.

## Recorded information

- Spell casts, impacts and periodic damage.
- Combat segments and boss encounters.
- Equipment, stats, talents and artifact snapshots.
- Player buffs, targets, movement and deaths.
- Manual markers and interface errors.
- Combustion windows, including Pyroblast casts and Meteor impacts.

Offensive damage is tracked separately from self damage, friendly damage and incoming damage.

## Saving and clearing recordings

1. Run `/rs stop`.
2. Run `/reload`.
3. Copy the exported file to a backup location.
4. Run `/rs clear` when you no longer need the saved sessions.
5. Run `/reload` to save the cleared database.

Recordings are written to disk when the interface reloads or the character logs out.
