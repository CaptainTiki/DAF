# Decisions

Judgment calls made while building, newest milestone first. Each entry says what was decided and why.

## Milestone 01: Ant farm

### Project layout
- `simulizer/` runs the simulation, `visualizer/` draws it, `ui/` is the HUD and tools, `data/` holds tunable Resources (`.tres`).
- `app/` was added for the composition root (`main.tscn`) and the window shell. It is the only place that knows about all the other folders.
- `tests/` holds GUT tests. `.tools/` holds dev scripts and is git-ignored.
- Dependencies run one way: `visualizer` and `ui` read `simulizer`; `simulizer` knows about neither.

### No autoloads, no signal bus
- `app/main.gd` creates the `Simulation` and passes it to the view, HUD and tool controller. All cross-system signal wiring is in that one file.
- Each object exposes its own signals (`Simulation.tile_changed`, `Storage.changed`, `RequestLog.changed`, `Hud.tool_selected`, and so on).
- The first plan was an event list the view drains each frame. Signals on the sim objects replaced it: several listeners (view, HUD, later the chronicle) can connect without a dispatcher.

### Simulation
- Plain `RefCounted` classes, no nodes. Fixed 20 ticks per second, driven by `SimClock`; speed-up runs more ticks per frame.
- One seeded `RandomNumberGenerator` owned by the sim, so a seed plus the same commands gives the same result. A test checks this.
- The grid is 160 x 124: 3 sky rows, 1 topsoil row, then 30 layers of 4. The handoff's 160 x 120 would have given 29 layers.
- Out-of-bounds tiles read as solid, so the world has walls without special cases.
- Tiles keep their material after being dug, so the back wall shows what was there.
- Each tile has a spare structure byte for the back lane (built stairs). Nothing writes it yet.

### Dwarves and jobs
- Reach is the four tiles in the column beside the dwarf. Since a dwarf can never dig their own column, the safety rule holds by construction.
- Another dwarf can still dig someone's floor away. Gravity handles it: the dwarf drops the job and falls to the next floor.
- Job choice is nearest first by walking distance. Hauling takes priority once more than 3 balls are waiting (`haul_priority_threshold`).
- Among equally near dig tiles the lowest goes first, so balls land on the floor instead of on a ledge.
- A job that fails is left alone for 5 seconds (`job_retry_ticks`) so dwarves don't retry it every tick.
- Idle dwarves wander a few tiles now and then, to keep the hold moving.
- Tiles more than one above head height can't be reached without scaffolding, so they stay marked. This is expected until scaffolding exists.

### Stairs (pulled forward from milestone 02)
- Hand-dug steps only go one way and are destroyed by digging next to them, so built stairs came early.
- Stairs are a structure in the tile's back-lane slot, separate from the rock in front. Planning them digs nothing.
- A stair tile can be stood on and never falls away. Steps onto, off and along stairs skip the headroom check, because the stairs have their own space behind the rock.
- The floor tile at the top of a flight stays solid, so dwarves on that floor walk straight across it.
- From the foot of a flight a dwarf can reach and dig the layer below, so stairs can lead into undug rock.
- The Stairs tool snaps a drag to a 45 degree line. One flight between layers is 3 tiles.
- Stairs cost nothing but time (`stair_build_ticks`). Materials come with the order chain.
- Cancelling removes plans only. Built stairs can't be removed yet; that needs a demolish tool that won't strand a dwarf inside rock.
- A stair tile and the head space above it are drawn cut away, even where the rock in front is intact. The dwarf on the stairs is seen whole.
- Where that cuts into a floor, a thin walkway strip is kept along the top, so dwarves crossing in front have something underfoot.
- In the front lane a dwarf always needs feet and head tiles open. Stairs are the one exception, because their space is behind the rock.

### Crowding
- When picking dig or build work, a spot another dwarf is already using counts as 4 steps further away. Dwarves spread along the work face when there is a choice.
- Dwarves can still share a tile when it is the only place to work from. Each stands at its own fixed spot within the tile (up to 0.3 of a tile either side of centre), so a group reads as a group.
- Each dwarf has a personal tempo, rolled at hiring: a pause of 0 to 0.3 s before acting on a decision, and walking and working up to 15% faster or slower. Pick swings also start at different points. Tunable with `think_ticks_max` and `pace_variation`.
- Idle dwarves sharing a tile move apart: all but the earliest hired wander off.

### Storage
- A hauler only picks a ball up if there is room for it. With no room the ball stays where it is and the dwarf posts the request. The handoff had the dwarf carry it and drop it nearby, which would loop forever.
- A ball is dropped on the spot only if its pallet disappears while it is being carried.
- Requests are keyed per material and refresh at most every 10 seconds.
- Unmarking a stockpile tile, or digging the floor from under it, spills the pallet back into loose balls.

### Rendering
- Compatibility renderer (OpenGL), for low GPU load on a desktop idler.
- 3D with an orthographic camera looking straight down -Z. Depth is a fixed set of Z lanes in `visualizer/view_space.gd`. A lane changes draw order only, never screen position.
- Tiles are flat quads in one MultiMesh, one instance per tile, unshaded. Lighting waits for the art pass.
- Rock is hidden unless it borders open space. The debug panel's "Reveal map" shows everything.
- Pooling: tiles, marks, balls and pallets are MultiMesh instances that are reused. Dwarf views are created once per dwarf and never freed.
- Stretch mode is off. With `canvas_items` the UI would shrink to a quarter size in a 150 px strip.

### Windows
- "Hide to tray" minimises the window and shows a tray icon that restores it. Godot can't hide its main window. This is the fallback the handoff allowed.
- Full screen uses Godot's borderless fullscreen mode.
- Frame caps: strip 30, corner 30, full screen 60, tray 5. Low-processor mode is on, so frames are only drawn when something changed.
- The last window mode is saved to `user://window.cfg`. Window position is fixed per mode, so it isn't saved.
- Window modes do nothing when the game is embedded in the editor. Turn off "Embed Game on Next Play" in the Game tab.

### Not done
- Auto-dig toggle (optional in the handoff).
- Background CPU load has not been measured.
