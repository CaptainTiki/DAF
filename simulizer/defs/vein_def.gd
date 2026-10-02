class_name VeinDef
extends Resource
## One kind of ore vein that can appear inside a depth band.

@export var material: MaterialDef
## How many veins to seed per 1000 tiles of the band.
@export var veins_per_thousand_tiles: float = 2.0
@export var min_size: int = 5
@export var max_size: int = 12
