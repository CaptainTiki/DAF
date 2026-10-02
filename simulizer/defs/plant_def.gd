class_name PlantDef
extends Resource
## Something that grows over time and is harvested for items: a surface tree,
## a farmed mushroom.

@export var id: StringName
@export var display_name: String
## Ticks from bare to ready for harvest.
@export var grow_ticks: int = 2400
## Each plant grows this much faster or slower than grow_ticks, rolled when it
## is planted (0.1 = up to 10% either way).
@export_range(0.0, 0.5) var growth_variation: float = 0.1
@export var harvest_ticks: int = 80
@export var yield_item: ItemDef
@export var yield_count: int = 1

@export_group("Look")
## Full-grown height in tiles.
@export var height: float = 2.0
@export var stem_color: Color = Color(0.45, 0.3, 0.15)
@export var cap_color: Color = Color(0.25, 0.55, 0.25)
## Width and height of the cap or canopy when full grown, in tiles.
@export var cap_size: Vector2 = Vector2(1.2, 1.0)
