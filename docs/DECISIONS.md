# Decisions

Judgment calls made while building, newest milestone first. Each entry says what was decided and why.

## Milestone 02: Order chain

### Items and storage
- A ball is now an item with a type (`ItemDef`): dirt, ores, wood, chair, table. Each material names the item it drops.
- Each item type has a size in storage units. A pile holds 10 units: ten balls, three chairs or two tables.
- Three kinds of pile: stockpile (one item type each, on tiles the player marks), output (beside a bench, mixed types) and supply (the starting goods, no limit).
- An empty stockpile pile gives its tile back, so another type can use it.

### Deliveries
- Any place can ask for items with a `Request`: a planned stair asks for wood, a bench for its inputs, a hall slot for a chair.
- Haulers serve requests first, taking the item from wherever is nearest (loose on the floor or in any pile). Loose items with no request go to the stockpile. Last, output and supply piles are cleared into the stockpile, but only items nobody is asking for.
- A request nobody can fill is reported in the requests log, unless a bench can make the item, in which case it is simply still being made.

### How dwarves pick work
- The old rule (everyone hauls once 3 balls are waiting) is gone.
- Kinds of work are ranked each time a dwarf looks. A kind with work waiting and nobody on it comes first, the longest-neglected at the front. After that, kinds are ranked by work waiting per dwarf already on it.
- A lone dwarf therefore alternates between kinds, and a crew splits itself across them.
- A dwarf who has worked at a bench treats it as a post: craft if ready, fetch its inputs, and haul only when its output pile is full. The craft job is kept for that dwarf for 10 seconds (`post_patience_ticks`) before anyone else may take it.

### Rooms
- The player picks a room type and drags over dug floor. The room snaps to the floor and the open space above it.
- Everything in a room is derived from its width by the room type's layout: a margin at each end and a set of slots that repeats every N tiles. Nobody places furniture.
- Room types are data (`data/rooms/*.tres`) with a category, minimum width and minimum open height.
- Hall: a chair and a table on every tile except one at each end. 5 wide gives 3 of each; 10 wide gives 8 of each.
- Carpentry: a 3-wide bench plus 1 output tile, repeating every 4 tiles. A wider workshop has more benches.
- Mushroom farm: a plot every 2 tiles.
- Rooms can't overlap each other or stockpile tiles, and can't go on the surface.
- Right-drag with the Room tool removes a room. Its furniture, bench materials and stored goods drop to the floor.

### Structures: stairs and floors
- The player can dig a room any height, so a floor is never inferred from where layers are. Ground is rock, or a floor a dwarf built. An earlier rule that put a walkway wherever stairs crossed a layer's floor row was removed for this reason.
- A built floor is a plank platform along the top of an open tile. Dwarves and items stand on it from the tile above; the space under it stays open. It splits a tall room into storeys, bridges a gap, or covers a stairwell.
- Structures are bits on the tile, so one tile can hold both a stair and a floor.
- Where a stair passes behind rock that hasn't been dug, the rock is still the floor. Dig it out and there is a hole until a floor is built over it; dwarves can still cross by dipping down the stair and back up.
- Stairs and floors cost 1 wood per tile (`structure_item`).
- Removing a plan cancels it at once. Removing something built marks it, and a dwarf walks over and takes it down (`remove_ticks`); the wood drops on the spot. Right-drag with the Remove tool takes the mark off again.
- Taking down starts at the far end of a run, so the dwarf works back towards the way out. A dwarf never takes down what they are standing on, waits while another dwarf is on it, and refuses if it would leave them with no way back to solid ground.
- The Build button opens a picker (Stairs, Floor, Remove); the Room picker has Remove too. Right-drag with any build or room tool also removes.
- Stairs are drawn as half planks from each stair tile towards each stair it touches, so runs that meet at a turn join up.
- Walls and doors are not built yet. A wall would turn open space back into solid; a door has nothing to do until there are threats.

### Scaffolding
- Scaffolding is a third structure: a platform like a floor that can also be climbed straight up and down. Climbing is the only vertical move in the game.
- Dwarves put it up by themselves. When a dwarf looks for digging and finds none in reach, the `Scaffolder` looks for a marked tile that is only out of reach because it is too high, and plans a tower beside it: straight up from a floor the dwarf can walk to, just tall enough to stand on and reach the tile.
- For digging only, a dwarf also reaches the tile straight above their head, as well as the column on each side. So from the top of a tower one dwarf digs three columns of ceiling. Carrying and building still work from beside only.
- A tower can stand beside the tile or directly under it. The spot that brings the most marked tiles into reach is chosen, then the shorter tower.
- The lowest stance that reaches is used, so towers are as short as they can be. The tallest allowed is 8 tiles (`scaffold_max_height`).
- A tower goes up from the bottom, each tile built by a dwarf standing in it. It costs 1 wood per tile.
- Every 2 seconds, towers with nothing marked for digging in reach are marked to come down. They come down from the top, and the wood drops at the foot.
- A tower only goes straight up from a floor. It doesn't bridge gaps or rescue a trapped dwarf; those stay as stairs and floors the player places.
- There is no player-placed scaffolding yet.

### Dirt and stone
- Dirt is waste (`dump` on the item). It is never stored. Dwarves carry it up to a spoil heap on the surface, 7 tiles left of where they arrived, and it is gone. The heap grows as a visible mound.
- If there is no way up to the heap, dirt stays where it fell and nobody complains.
- The dirt layer is thin now: about the top 6 rows. Below that it is stone.
- Stairs and floors can be built from wood or stone, chosen with a button in the Build picker (`build_materials`). Both cost 1 per tile. What a structure is made of is remembered, drawn in that colour, and given back when it is taken down.
- Scaffolding is always wood.
- Stone does not count as higher quality yet. Nothing measures quality.
- Not built yet: walls, a mason's workshop, stone furniture.

### Needs and mood
- A need is data (`NeedDef`): how fast it runs down, how fast it is restored, when a dwarf goes to see to it, and what they say. Sleep is the only one so far.
- A need is asleep until something in the hold can satisfy it. With no bunk built, nobody gets tired. This replaces any "turn needs on" switch.
- A room slot says which need it satisfies (`satisfies` on the slot). A bunk satisfies sleep.
- Sleep runs out in 8 minutes and is restored in 1. A dwarf goes to bed between jobs once it drops below 35%. A sleeping dwarf does not get up for work.
- A bunk belongs to the first dwarf who uses it, and they go back to the same one.
- Mood has three levels. Bad: some need has run out. Good: a need is in play and all are above half. Ok: otherwise, including a hold with no needs in play.
- Bad mood makes walking and working take 30% longer; good mood 15% less (`bad_mood_pace`, `good_mood_pace`).
- There is no death, no arrivals and no hunger, drink or fun yet.
- A dwarf with no bunk free says "tired!" and reports it in the requests log.
- Mood is not shown anywhere yet, other than by what a dwarf says.

### Food and drink
- Two more needs, both data files: food (runs out in 12 minutes, eaten in 8 seconds) and drink (10 minutes, 6 seconds). Both are seen to at a dining seat: the hall's chairs.
- A need that consumes something (a meal, an ale) is in play only once there is somewhere to sit and a station that can make it, or some already to hand.
- A hungry dwarf fetches their own meal: they claim a seat, ask for a meal at it, go and get one from wherever it is (loose, a pile, the kitchen's output), carry it to the seat and eat it there. Nobody else fetches it for them, and the request is theirs alone.
- If there is no meal anywhere they say so ("nothing to eat") and get on with work, hungry.
- Kitchens cook to demand: every hungry dwarf who hasn't set off for a meal counts as wanting one, plus a stock of 2 kept ready (`stock_target`). The brewery works the same way for ale.
- Two mushroom farms: the mushroom grove grows mushroom trees for wood; the mushroom patch grows cap mushrooms for food, two per plot every 90 seconds. A meal is 2 mushrooms at the kitchen; an ale is 2 mushrooms at the brewery.
- The kitchen's stove costs 4 stone; the brewery's fermenter costs 4 wood.
- Dirt is now the top 2 rows only, with pockets of dirt in the stone below.

### Dwarves speak
- A dwarf has a `speech` string, drawn in a bubble over their head. For now the only thing said is "!".
- An idle dwarf checks every 5 seconds whether they can still walk back to where the dwarves arrived. One who can't is trapped: they show "!" and post "I'm trapped! Build stairs to me." in the requests log. It clears once a way out exists.
- The check only runs when idle, so a dwarf who is cut off but still has work in reach keeps working and says nothing until it runs out.

### Joining rooms
- A room dragged so that it touches or overlaps a room of the same type becomes one room with it. A new room can bridge two others.
- The layout is recalculated for the new width. A slot that is still in the layout keeps what it has: built furniture, a bench and its output pile, materials already delivered.
- The layout stays lined up with the leftmost room that was joined, so benches never move when a workshop is extended. Extending by an odd width leaves spare tiles at the end.
- Rooms of different types never join, and still can't overlap.

### Making things
- Nobody queues orders. Every 10 ticks, for each recipe: items being asked for, minus items on hand, minus items already being made, becomes pending orders. So exactly what is wanted gets made.
- A bench takes one order, asks for its inputs, and offers a craft job once they are in and its output pile has room.
- Furniture is installed the moment it is delivered to its slot; there is no separate install job.
- A bench costs 4 wood and is built in place. A chair costs 1 wood, a table 2, a stair tile 1.

### The start
- No pre-dug room. Dwarves arrive on the surface beside 10 wood.
- 8 sky rows (was 3), so the surface has room for trees. The grid is 160 x 129.
- Surface trees and farm mushrooms are the same thing (`PlantDef`): they grow, offer a harvest job when full grown, drop items and regrow. A tree gives 3 wood every 8 minutes; a mushroom gives 1 wood every 2 minutes.
- Trees are always cut when full grown. There is no chop tool.
- Each plant rolls its own growth speed when planted, up to 10% faster or slower (`growth_variation` on the plant type). The roll is kept for the plant's life, so some plots are always the quick ones.
- A full-grown plant shows extra foliage sticking out of its square outline, so ripe ones can be told from nearly-ripe ones.

### HUD
- Window modes are four icon buttons stacked down the right edge. Beside them is a second column: normal, double and triple speed, the room colour overlay, and planned (unbuilt) furniture.
- Speeds x4 and x16 stay in the debug panel.

### Sitting
- An idle dwarf about to wander may sit on a free chair instead, facing the camera, behind the table. They still check for work and get up for it.
- There is no food or hunger yet; sitting is only a place to be idle.

### Window
- The project's stretch mode scales the UI with the window. That is kept for full screen. In the strip and corner the window controller turns it off, because there it would shrink the UI to a quarter size.

### Not done
- Digging the floor out from under a room, a bench or a tree is not handled; they stay where they are.
- Trees are drawn slightly cut off at the top in the strip view.

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
