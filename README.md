# Auto Trail Lights

A mod for **Ski-E-O! Ski Resort Tycoon**, made for [Z's Mod Loader](https://mods.bigz.studio/), that lights a whole trail for night skiing in one click.

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

**Back up your saves first.** Copy `%LOCALAPPDATA%\Ski-E-O\SaveGames` somewhere safe before you use any mod.
Steam Cloud syncs that folder, so a broken save can reach your other PCs too.

1. Install [Z's Mod Loader](https://mods.bigz.studio/) with its installer, then open **Ski-E-O Mod Manager**.
2. Under **Discover**, find **Auto Trail Lights** and install it. It's listed once the release is approved.
   - To install by hand instead, copy the [`AutoTrailLights`](AutoTrailLights) folder into the game's `mods` folder
     (`skieogame\mods\`), then turn it on under **Mods → Installed**.
3. Start the game.

The Mod Manager can switch the mod off and on while the game is running. Lights you've already placed stay.

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

- Tested with game builds CL7848 and CL7918 on Z's Mod Loader 1.3.
- Single-player game; the mod contains no game files.

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Loader:** [Z's Mod Loader](https://mods.bigz.studio/).

## License

[MIT](LICENSE)
