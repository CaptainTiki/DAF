class_name DepthBand
extends Resource
## A horizontal slice of the world with its own base material and vein table.

## Where the band starts, as a fraction of the ground depth (0 = surface, 1 = bottom).
@export_range(0.0, 1.0) var start_depth: float = 0.0
@export var base_material: MaterialDef
@export var veins: Array[VeinDef] = []
