# Little Computer Dwarves: Light GDD

*Working title. Living document, so expect it to change.*

## Pitch

A desktop strip idler. A side-view cross-section of an underground dwarf hold sits along the bottom of your screen while you work. Little dwarves dig, haul, stack, build and complain, all on their own. You set direction (where to dig, what to build) and glance down whenever something catches your eye.

Spiritual ancestor: *Little Computer People* (C64). Genre neighbours: *Rusty's Retirement* (format), *Dwarf Fortress* (job chains, much lighter).

**Goal:** a commercially viable Steam release. The current work is a prototype that we intend to keep building on if it proves out. It is not a throwaway.

## Design pillars

1. **Something is always happening.** Every system should produce visible, small, staggered motion: walking, carrying, chipping, stacking. Work hidden inside buildings is a failure.
2. **The screen is the progress bar.** After two hours away, the hold should *look* different: more tunnels, bigger piles, more dwarves.
3. **Systems make the show.** Motion comes from real needs → orders → jobs → hauling, not from canned animation loops.
4. **Shallow chains, deep feel.** Production chains stay 2–3 links deep (wood → chair). Never a spreadsheet.
5. **Glanceable.** Readable at strip size (~150px tall). Events that matter get a small visible callout.

## Format and windows

- **Strip** (default): borderless, always-on-top band along the bottom of the screen, about 150px tall, full width, showing about 2 layers. Up/down buttons move the view between layers.
- **Full screen**: free pan/zoom, for ogling.
- **Corner**: a small floating window.
- **Tray**: hide to the system tray while the sim keeps running.
- Windows first (the only test platform for now).

## World

- Side-view tile grid. Small tiles, so digging reads as chipping rather than squares popping.
- **Layer = 4 tiles tall:** 1 floor tile + 3 open tiles. A natural room is 3 tiles tall.
- Materials are rolled by depth: dirt near the surface, then rock with iron/copper veins, then silver/gold, with gems deep. Weighted so iron is common and gold is rare. Veins come in clumps.
- Later depth bands each bring a new palette, new resources and new threats (crystal caverns, magma, ancient ruins, things coming up from below).

## Dwarves

- 2 tiles tall. They can walk, and step up or down 1 tile.
- **Reach:** the 4 tiles in the column beside them: below feet, feet, head, above head.
- A standing dwarf can dig a full 3-tall room. Taller or deeper work needs **scaffolding** (planned v2).
- They can dig stairs naturally: dig below-and-in-front, step down, repeat.
- Personality stays light: name, job, beard length (grows with experience). No moods or family trees.

## Core loops

**Ant farm (first milestone):** mark tiles to dig → dwarves chip them → resource balls drop → haulers carry balls to stockpile pallets → full pallet means a new pallet goes down → no room means a request in the log ("need more storage").

**Later, the order chain:** a dug room gets a purpose (hall, workshop, farm, bunks), and a purpose posts needs (table + chairs). Needs become jobs (carpenter builds a chair), jobs need inputs (mushroom wood), and inputs need hauling (a dwarf walks to the farm). Everything is visible.

**Economy (later):** sell goods to surface caravans for gold. Gold hires dwarves, buys tools and unlocks deeper layers.

## Stairs (planned)

- Test stairs are hand-dug dirt steps.
- Real stairs are a *built* structure that sits in a **back lane**, so dwarves walking along a floor pass *in front of* the stairs and the floor walkway stays clear.
- Once built stairs exist, the old dirt steps can be dug or filled away.
- A Stairs tool comes soon after the first play: mark a diagonal and dwarves dig and build it.

## Player tools

Tools bar along the bottom (full screen; compact in strip):
- **Dig** (first): drag a rectangle to mark tiles.
- **Stockpile**: drag on a floor to mark storage space.
- Later: Stairs, Room purpose, Build, Scaffolding, Cancel.

## Requests log → chronicle

- Dwarves who hit a problem post it to a readable log ("Brokk: stockpile's full, no room for a new pallet.").
- This later grows into actionable requests (with buttons), plus a **"while you were away"** chronicle of notable events. That chronicle is a key retention hook.

## Art and audio direction

- Low-poly 3D, orthographic side camera, palette-texture UVs (PixPal-style swatches, no vertex colors). Warm torchlight against dark rock. Each depth band shifts the palette.
- Audio is wanted: soft pick taps, distant hammering, ambient cave tone, small chimes for discoveries. It has to be quiet and pleasant enough to run all day. It's absent from the first prototype only for speed.

## Open questions

- What is the long-term goal or prestige? (A deepest-layer story beat? Founding a second hold?)
- How much do threats (goblins, cave-ins, floods) matter vs. pure building?
- Offline progress: full sim catch-up or summarized?
- Pricing and scope target for a first Steam release.

## Roadmap sketch (sequencing, not limits)

1. **Ant farm:** dig, drop, haul, pallets, requests log, window modes. *(current)*
2. Stairs tool + built back-lane stairs, scaffolding.
3. Room purposes + first order chain (hall → carpenter → mushroom wood).
4. Surface, caravans, gold, hiring.
5. Save/load + offline progress + chronicle.
6. Art pass, audio, depth bands, threats.
7. Steam page / demo.
