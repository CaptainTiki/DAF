class_name SimConfig
extends Resource
## Tunables for the whole simulation. Times are in sim ticks.

@export var ticks_per_second: int = 20
## Tile material index = position in this array.
@export var materials: Array[MaterialDef] = []
@export var world_gen: WorldGenConfig

@export_group("Dwarves")
@export var walk_ticks: int = 6
@export var fall_ticks: int = 2
## How often an idle dwarf looks for work.
@export var idle_retry_ticks: int = 20
@export_range(0.0, 1.0) var wander_chance: float = 0.25
@export var wander_range: int = 6
## How long a job that just failed is left alone before anyone retries it.
@export var job_retry_ticks: int = 100
@export var dwarf_names: PackedStringArray = []

@export_group("Jobs and storage")
## Ticks to build one tile of stairs.
@export var stair_build_ticks: int = 50
@export var pallet_capacity: int = 10
## Dwarves prefer hauling over digging once more than this many balls are waiting.
@export var haul_priority_threshold: int = 3
## Minimum gap before a repeated request bumps its count again.
@export var request_refresh_ticks: int = 200
