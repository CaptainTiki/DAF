# Handoff 01: Ant Farm Prototype

**Project:** Little Computer Dwarves (working title), a desktop strip idler in Godot 4. Read `GDD.md` first for the full vision.

## Read this first: how to treat this doc

This is the **first milestone of a project we intend to grow into a commercial product.** It is not the whole project, and it's not a throwaway prototype.

- **Scope here is sequencing, not a rulebook.** Anything listed under "Not in this milestone" just means *not yet*. Nothing in this doc says sound, art, saving, menus or any other feature is forbidden or out of the project.
- **Build for growth.** Structure code so the GDD's later systems (orders, room purposes, built stairs, scaffolding, save/offline progress) can land without rewrites. Don't over-engineer for them, but don't paint into corners either.
- **Make reasonable calls.** If something here is ambiguous or turns out to be a bad idea in practice, pick the sensible option, keep going, and note what you decided and why in `DECISIONS.md`.
- Greybox visuals are fine. Make it work and feel alive first.

## Milestone goal

**"Does the ant farm feel alive?"** Hire a few dwarves, mark some digging, and watch them chip tiles, drop resource balls, carry them to a stockpile and stack pallets, with no game wrapped around it yet. If that's pleasant to watch on a strip at the bottom of the screen, the core works.

## Conventions (John's)

- Godot 4.x, GDScript, `class_name` with explicit static typing everywhere.
- Scenes-first composition, node-first authoring; content and config as Resources.
- Prefer direct, clear ownership over signal-bus indirection.
- Pool dynamic objects (dwarves, resource balls, pallets) rather than instancing and freeing freely.
- **Keep the simulation separate from presentation.** Sim state (grid, dwarves, jobs, items) lives in plain data/logic classes ticked at a fixed rate. Visual nodes read from it. This keeps save/load, offline catch-up and speed-up possible later.
- Windows is the target platform.

## World

- **Tile grid**, side view. Suggested starting size: about 160 wide × 120 tall (30 layers). Make it configurable.
- **Layer = 4 tiles tall:** row 0 is floor, rows 1–3 are open space once dug. Layers matter for the camera and labels; the sim itself is just a tile grid.
- **Tile data:** material type, and whether it's solid or open. Also leave room for a per-tile "back lane" or structure slot, because built stairs will live in a back lane later (see GDD).
- **Materials:** Dirt, Stone, Copper, Iron, Silver, Gold, Gem. Use Resources for definitions (color, hardness/dig time, drop type).
- **Generation:** depth bands with weighted tables (dirt-heavy near top, rock middle with iron/copper, silver/gold deeper, gems deepest; iron ≫ gold). Ores come in **clumped veins** (noise or random walks), not scattered single tiles. Keep the band tables in a Resource so they're easy to tune.
- **Surface:** the top couple of rows are sky/grass. Start with a small pre-dug entry room on layer 1 for the dwarves to spawn in.
- **Rendering:** the intended final look is low-poly 3D with an orthographic side camera (GDD art direction). For greybox, either a 3D setup (GridMap or MultiMesh boxes, ortho camera) or 2D is acceptable. Prefer the 3D route if it's not much slower, since that's where art will land. Tiles must update individually as they're dug.

## Dwarves

- **Size:** 2 tiles tall, 1 wide.
- **Movement:** walk left/right on solid ground; step up or down 1 tile. They need 2 open tiles of headroom. Gravity applies if the ground disappears (fall to the next floor).
- **Pathfinding:** grid search over walkable positions using those moves. Simple and cheap; the side view keeps it small.
- **Reach:** a dwarf can dig the **4 tiles in the column directly beside him**: below feet, feet, head, above head.
- **Safety rule:** a dwarf must never dig a tile he's standing on or the tile he needs to stand on to reach his target. Only claim tiles reachable from solid, walkable ground.
- **Dig time** is per material (dirt fast, stone slower, ore slower, gems slowest). Show it with a pick-swing placeholder and a progress tick or small chips.
- Give each dwarf a generated name. Beard length can be a field even if unused yet.

## Jobs

- A central **job board.** Jobs are claimed by one dwarf at a time and released if he can't complete them.
- **Dig job:** one per marked solid tile. The dwarf walks to a valid standing spot and digs; when the tile is done it becomes open, and a resource ball drops.
- **Haul job:** one per loose ball not on a pallet. The dwarf walks to the ball, picks it up (visibly carried), walks to a pallet with space for that type and drops it.
- For now every dwarf can do every job. Pick by simple priority + distance (e.g. haul if loose balls exceed N, otherwise dig). Tunable; job roles/professions come later.

## Resource balls and storage

- **Balls:** one per dug tile, colored by material. They fall straight down to the floor (grid gravity, not physics) and sit there until hauled.
- **Stockpile tool:** drag a rectangle on open floor to mark storage tiles.
- **Pallets:** each holds a single resource type, stacking up to N balls (start N=10) in a visible stack.
  - Haulers prefer a non-full pallet of the matching type.
  - If none exists, they place a new pallet on a free stockpile tile.
  - If there's no free stockpile tile, the dwarf posts a request ("No room for a new pallet") and drops the ball nearby. Requests are deduped and refreshed rather than spammed.
- A simple resource total readout (counts per type).

## Player tools and UI

- **Tools bar** at the bottom: **Dig** (drag rectangle marks solid tiles; drag again or use a modifier to unmark) and **Stockpile** (drag rectangle on floor tiles). Marked tiles show an overlay.
- **Requests log:** a button opens a panel listing dwarf requests (dwarf name, message, time, count if repeated).
- **Debug panel:** Hire Dwarf (spawns at entrance), sim speed ×1 / ×4 / ×16, reveal map toggle. Optional auto-dig toggle if cheap.

## Window modes

- **Strip:** borderless, always-on-top, full screen width, ~150px tall, docked to the bottom of the primary screen above the taskbar. Height configurable. Shows about 2 layers.
  - Buttons on the strip edge: **layer up / layer down** (camera snaps by layer), **full screen**, **corner**, **hide to tray**.
  - Mouse wheel or drag pans horizontally.
- **Full screen:** free pan + zoom.
- **Corner:** small window (~480×270) in a screen corner.
- **Tray:** hide the window and keep the sim running. The tray icon restores it (Godot 4.3+ `StatusIndicator`). If tray proves fiddly, minimize is an acceptable fallback; note it in `DECISIONS.md`.
- Keep idle CPU low: cap FPS in strip/corner/tray and don't burn frames when nothing visual changes.
- Remember the last mode and position between runs if it's cheap. Not required.

## Done when

- [ ] Grid generates with depth-weighted materials and visible veins
- [ ] Hire Dwarf works; dwarves idle in the entry room
- [ ] Drag-marking Dig tiles makes dwarves walk over, chip them tile by tile and respect the reach and safety rules
- [ ] Hand-dug one-tile-down steps let dwarves descend and climb back up
- [ ] Balls drop, get hauled, stack on pallets, and new pallets appear when full
- [ ] A full stockpile posts a request to the log
- [ ] Strip / full screen / corner / tray all work, and layer up/down works in strip
- [ ] Runs comfortably in the background without noticeable CPU load
- [ ] `DECISIONS.md` notes any judgment calls

## Not in this milestone (yet)

These are planned and welcome later. They just aren't the focus right now:
- Sound and music (planned; quiet ambient audio is part of the vision)
- Final art, models, lighting, palette texture work
- Built stairs, back-lane stairs, Stairs tool, scaffolding
- Room purposes, orders, crafting chains, professions
- Surface economy, caravans, gold, hiring costs
- Save/load, offline progress, chronicle
- Threats, events, depth-band biomes
- Menus, settings, Steam integration

If adding a small hook for one of these now (an audio bus, an event signal for the chronicle, a serializable sim state) is cheap and natural, go ahead.
