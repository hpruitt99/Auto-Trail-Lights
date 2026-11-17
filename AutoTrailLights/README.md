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

1. Install [Z's Mod Loader](https://mods.bigz.studio/) with its installer, then open **Ski-E-O Mod Manager**.
2. Under **Discover**, find **Auto Trail Lights** and install it. It's listed once the release is approved.
   - To install by hand instead, copy the `AutoTrailLights` folder into the game's `mods` folder
     (`skieogame\mods\`), then turn it on under **Mods → Installed**.
3. Start the game.

The Mod Manager can switch the mod off and on while the game is running. Lights you've already placed stay.

## Notes

- There's no key to press; everything is in the trail panel.
- Lights go in one per frame, so you can watch them appear along the trail. The button counts up while it works. A
  long trail takes a second or two, and the game doesn't freeze.
- Bowls don't get the section, because they're open areas without two edges to line with lights.
- The game only loads the Tower Light once a resort has one. So in a resort with none yet, the first install
  picks the Tower Light in the build menu for a moment, which loads it. Anything you were placing at that
  moment is cancelled.
- Tower Lights must be unlocked in the resort. If they aren't yet, the panel says so.
- Lights go 4.5 m outside the trail's edge. Spots steeper than the game allows for a Tower Light (40°), on another
  trail, or within 8 m of a building are skipped or moved a little along the edge. Trees under a light are cleared, and the clearing
  is charged the way the game charges it.
- Very wide trails need more lights. Parts that are too far from either edge for any light to reach stay dark, and
  the panel says when that happens.
- Tested with game builds CL7848 and CL7918 on Z's Mod Loader 1.3.

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Assets:** uses the game's own Tower Light. The mod contains no game files.
- **Loader:** Z's Mod Loader (https://mods.bigz.studio/).
