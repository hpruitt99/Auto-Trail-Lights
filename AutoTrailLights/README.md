# Auto Trail Lights

A Lua mod for Ski-E-O! Ski Resort Tycoon that lights a whole trail for night skiing in one click.

## What it does

Click a trail and open its **Edit** tab. At the bottom there's a **Trail lights** section:

- **Uniform**: pairs of Tower Lights face each other across the trail.
- **Jagged**: a zipper. The spacing is the same, but each light faces a gap on the other side.
- **Install trail lights $X**: places the game's own Tower Light along both edges of the trail. They're evenly
  spaced and close enough that the whole trail is lit. The button charges their normal price and turns Night skiing
  on for that trail.
- After that, pick the other style and click **Switch to …** to swap the layout. The old lights are sold back first,
  and the new lights keep the trail's color. **Remove** takes this trail's lights away and refunds them.
- **Light color** appears once the trail has lights. It has 8 swatches: Warm white (the game's own), Cool white, Blue,
  Green, Red, Purple, Amber and Pink. There's also **Custom color**, which opens R/G/B sliders and shows the color
  while you drag. Color changes are free and recolor both the light beam and the lamp head of every light on the
  trail.
- **Party** sits next to Custom color. It turns the trail's lights into an RGB light strip: a rainbow that chases down
  the trail, with facing lights always the same color. Click it again to go back to warm white.

The mod only touches lights it placed itself, named "*Trail name* Light #*n*". A colored light's name ends with its
color, as in "Upper Parlor Light #3 · Blue". The mod leaves Tower Lights you place by hand alone, and it never
touches another trail's lights. The names are kept in your save. The game doesn't save light colors, so after a
reload the mod reads each color from the light's name and puts it back within a few seconds. The lights are ordinary
Tower Lights, so you can still select, move or bulldoze them one by one.

## Install

1. Install UE4SS: the Map Creator does this, or use UE4SS 3.0.1 in `SkiResortSimulator\Binaries\Win64`.
2. Copy the `AutoTrailLights` folder into `SkiResortSimulator\Binaries\Win64\ue4ss\Mods\`.
3. Add the line `AutoTrailLights : 1` to `ue4ss\Mods\mods.txt`, above `Keybinds : 1` if that line is there.
4. Start the game. `ue4ss\UE4SS.log` should show `[AutoTrailLights] loaded`.

## Notes

- There's no key to press; everything is in the trail panel.
- Lights go in one per frame, so you can watch them appear along the trail. The button counts up while it works. A
  long trail takes a second or two, and the game doesn't freeze.
- Bowls don't get the section, because they're open areas without two edges to line with lights.
- Lights go 4.5 m outside the trail's edge. Spots steeper than the game allows for a Tower Light (40°), on another
  trail, or within 8 m of a building are skipped or moved a little along the edge. Trees under a light are cleared, and the clearing
  is charged the way the game charges it.
- Very wide trails need more lights. Parts that are too far from either edge for any light to reach stay dark, and
  the panel says when that happens.
- Tested with game build CL7848 (2026-11-15) and UE4SS 3.0.1 beta (git 83330635).

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Assets:** uses the game's own Tower Light. The mod contains no game files.
- **Loader:** UE4SS (RE-UE4SS, MIT).
