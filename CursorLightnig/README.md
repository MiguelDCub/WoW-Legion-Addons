# CursorLightnig

Adds a lightning effect that follows the mouse cursor in **World of Warcraft: Legion 7.3.5** (interface `70300`).

## Installation

1. Copy the `CursorLightnig` folder into `Interface/AddOns/`.
2. Restart the game.
3. Enable **CursorLightnig** in the AddOns list.

## Usage

The lightning effect is enabled by default. It follows the cursor and stays at its last position while a mouse button is held or mouse look is active.

## Commands

| Command | Description |
| --- | --- |
| `/cursorlightnig on` | Enable the effect. |
| `/cursorlightnig off` | Disable the effect. |
| `/cursorlightnig reload` | Reload the effect. |
| `/cursorlightnig scale 1` | Set effect scale, from 0.05 to 10. |
| `/cursorlightnig alpha 1` | Set opacity, from 0.05 to 1. |
| `/cursorlightnig offset 0 0` | Adjust horizontal and vertical offsets. |
| `/cursorlightnig resetoffset` | Reset offsets. |

Settings are saved in `CursorLightnigDB`.
