class_name Storage
extends RefCounted
## Stockpile tiles and the pallets standing on them, plus running resource totals.

signal changed

var pallets: Dictionary[Vector2i, Pallet] = {}
## Stored ball count per material index.
var totals: PackedInt32Array

var _tiles: Dictionary[Vector2i, bool] = {}


func _init(material_count: int) -> void:
	totals.resize(material_count)


func tile_count() -> int:
	return _tiles.size()


func has_tile(tile: Vector2i) -> bool:
	return _tiles.has(tile)


func add_tile(tile: Vector2i) -> void:
	_tiles[tile] = true


## Removes a stockpile tile. Returns the pallet that stood there, if any,
## so the caller can spill its contents.
func remove_tile(tile: Vector2i) -> Pallet:
	_tiles.erase(tile)
	var pallet: Pallet = pallets.get(tile)
	if pallet == null:
		return null
	pallets.erase(tile)
	if pallet.placed:
		totals[pallet.material] -= pallet.count
		changed.emit()
	return pallet


## Claims room for one ball: a matching pallet with space if one can be reached,
## otherwise a new pallet on a free stockpile tile. Null when there is no room.
func reserve(material: int, near: Vector2i, flood_map: FloodMap, capacity: int) -> Pallet:
	var best: Pallet = null
	var best_score: int = 0
	for pallet: Pallet in pallets.values():
		if pallet.material != material or pallet.count + pallet.reserved >= capacity:
			continue
		if Pathfinder.best_access(flood_map, pallet.tile.x, pallet.tile.y, true) == Pathfinder.NO_SPOT:
			continue
		var score: int = _manhattan(pallet.tile, near)
		if best == null or score < best_score:
			best = pallet
			best_score = score
	if best != null:
		best.reserved += 1
		return best

	var best_tile := Pathfinder.NO_SPOT
	for tile: Vector2i in _tiles:
		if pallets.has(tile):
			continue
		if Pathfinder.best_access(flood_map, tile.x, tile.y, true) == Pathfinder.NO_SPOT:
			continue
		var score: int = _manhattan(tile, near)
		if best_tile == Pathfinder.NO_SPOT or score < best_score:
			best_tile = tile
			best_score = score
	if best_tile == Pathfinder.NO_SPOT:
		return null
	var created := Pallet.new()
	created.tile = best_tile
	created.material = material
	created.reserved = 1
	pallets[best_tile] = created
	return created


## Gives back a reservation that won't be used.
func release(pallet: Pallet) -> void:
	pallet.reserved = maxi(pallet.reserved - 1, 0)
	if not pallet.placed and pallet.reserved == 0 and is_current(pallet):
		pallets.erase(pallet.tile)


## Adds a reserved ball to the pallet.
func deposit(pallet: Pallet) -> void:
	pallet.reserved = maxi(pallet.reserved - 1, 0)
	pallet.count += 1
	pallet.placed = true
	totals[pallet.material] += 1
	changed.emit()


## False once the pallet's stockpile tile has been removed from under it.
func is_current(pallet: Pallet) -> bool:
	return pallets.get(pallet.tile) == pallet


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
