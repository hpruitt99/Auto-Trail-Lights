# Auto Trail Lights

A UE4SS Lua mod for **Ski-E-O! Ski Resort Tycoon** that lights a whole trail for night skiing in one click.

Open a trail's panel and go to the **Edit** tab. The **Trail lights** section places the game's own Tower Lights
along both edges of the trail. They're evenly spaced and close enough that the whole run is lit. The section charges
the normal price and turns Night skiing on.

- **Styles:** *Uniform* puts pairs of lights facing each other across the trail. *Jagged* is a zipper: the same
  spacing, but each light faces a gap on the other side. You can switch styles later; the old lights are sold back.
- **Colors:** 8 presets, or custom R/G/B sliders. The color changes both the beam and the lamp head, and is free.
- **Party:** an RGB-light-strip rainbow that chases down the trail.
- **Remove:** takes a trail's lights away and refunds them.
- **Your lights are safe:** the mod only manages the lights it placed. It leaves hand-placed lights and other trails'
  lights alone.
- **Smooth:** lights go in one per frame, so the game never freezes.

## Install

1. Install UE4SS 3.0.1 into `SkiResortSimulator\Binaries\Win64`. The Ski-E-O Map Creator does this for you.
2. Copy the [`AutoTrailLights`](AutoTrailLights) folder into `SkiResortSimulator\Binaries\Win64\ue4ss\Mods\`.
3. Add the line `AutoTrailLights : 1` to `ue4ss\Mods\mods.txt`, above `Keybinds : 1` if that line is there.
4. Start the game. `ue4ss\UE4SS.log` should show `[AutoTrailLights] loaded`.

The mod folder's own [README](AutoTrailLights/README.md) has the details on how it places lights, and its limits.

## How it works

The script is all in [`AutoTrailLights/Scripts/main.lua`](AutoTrailLights/Scripts/main.lua):

- **Trail shape:** read from `TrailMapSubsystem.RegisteredTrails` (curves plus corridor width). The game's own
  `IsPositionInCorridor` decides what counts as the trail.
- **Spacing:** the widest even spacing at which the lights' 50 m light zones still cover the whole trail.
- **Placing:** a deferred spawn of `BP_TowerLight`, then `FinalizePlacement`, then `TryDeductFunds`, the same steps as
  a normal placement.
- **Colors:** the game doesn't save light colors, so the mod keeps each color in the light's name ("Upper Parlor
  Light #3 · Blue") and reapplies it after a reload.

## Compatibility

- Tested with game build CL7848 (2026-11-15) and UE4SS 3.0.1 beta (git 83330635).
- Single-player game; the mod contains no game files.

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Loader:** [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT).
- **Map Creator:** thanks to the Ski-E-O Map Creator community for its modding notes.

## License

[MIT](LICENSE)
