class_name SimConfig
extends Resource
## Tunables for the whole simulation. Times are in sim ticks.

@export var ticks_per_second: int = 20
## Tile material index = position in this array.
@export var materials: Array[MaterialDef] = []
## Item type index = position in this array.
@export var items: Array[ItemDef] = []
@export var recipes: Array[RecipeDef] = []
## Room types offered to the player, in picker order.
@export var rooms: Array[RoomDef] = []
## What dwarves need from time to time. Need index = position in this array.
@export var needs: Array[NeedDef] = []
@export var world_gen: WorldGenConfig

@export_group("Start")
@export var starting_item: ItemDef
@export var starting_item_count: int = 10

@export_group("Dwarves")
@export var walk_ticks: int = 6
@export var fall_ticks: int = 2
## How often an idle dwarf looks for work.
@export var idle_retry_ticks: int = 20
@export_range(0.0, 1.0) var wander_chance: float = 0.25
@export var wander_range: int = 6
## Chance that an idle dwarf about to wander goes to sit down instead, if a seat is free.
@export_range(0.0, 1.0) var sit_chance: float = 0.6
@export var sit_ticks_min: int = 200
@export var sit_ticks_max: int = 600
## How long a job that just failed is left alone before anyone retries it.
@export var job_retry_ticks: int = 100
@export var dwarf_names: PackedStringArray = []
## How often an idle dwarf checks whether they can still walk home.
@export var trapped_check_ticks: int = 100
## Each dwarf gets a fixed pause of 0..this many ticks before acting on a new
## decision, so a group never moves as one.
@export var think_ticks_max: int = 6
## Each dwarf walks and works this much faster or slower than average (0.15 = up to 15%).
@export_range(0.0, 0.5) var pace_variation: float = 0.15

@export_group("Mood")
## How much longer walking and working take in a bad mood (1.3 = 30% longer).
@export var bad_mood_pace: float = 1.3
## The same for a good mood (0.85 = 15% quicker).
@export var good_mood_pace: float = 0.85

@export_group("Jobs and storage")
## How long a station's craft job is kept for the dwarf whose post it is,
## before anyone else may take it.
@export var post_patience_ticks: int = 200
## Ticks to build one tile of stairs once its materials are there.
@export var stair_build_ticks: int = 50
## Ticks to build one tile of floor once its materials are there.
@export var floor_build_ticks: int = 40
## Ticks to put up one tile of scaffolding once its materials are there.
@export var scaffold_build_ticks: int = 30
## The tallest tower dwarves will put up by themselves, in tiles.
@export var scaffold_max_height: int = 8
## Ticks to take down one tile of stairs or floor.
@export var remove_ticks: int = 30
## What a tile of stairs or floor is made of. Null makes structures free.
@export var structure_item: ItemDef
@export var structure_item_count: int = 1
## Storage units a pile holds. An item takes ItemDef.size units.
@export var pile_capacity: int = 10
## Minimum gap before a repeated request bumps its count again.
@export var request_refresh_ticks: int = 200
