class_name Storage
extends RefCounted
## Every pile in the hold, the stockpile tiles the player has marked, and
## running totals of what is stored.

signal changed

var piles: Array[Pile] = []
## Stored item count per item type, across all piles.
var totals: PackedInt32Array

var _sizes: PackedInt32Array
var _stockpile_capacity: int
var _stock_tiles: Dictionary[Vector2i, bool] = {}
var _stock_piles: Dictionary[Vector2i, Pile] = {}


func _init(items: Array[ItemDef], stockpile_capacity: int) -> void:
	totals.resize(items.size())
	for item: ItemDef in items:
		_sizes.append(item.size)
	_stockpile_capacity = stockpile_capacity


func size_of(type: int) -> int:
	return _sizes[type]


# --- Stockpile tiles ---

func tile_count() -> int:
	return _stock_tiles.size()


func has_tile(tile: Vector2i) -> bool:
	return _stock_tiles.has(tile)


func add_tile(tile: Vector2i) -> void:
	_stock_tiles[tile] = true


## Unmarks a stockpile tile. Returns the pile that stood there, if any, already
## taken out of storage, so the caller can spill its contents.
func remove_tile(tile: Vector2i) -> Pile:
	_stock_tiles.erase(tile)
	var pile: Pile = _stock_piles.get(tile)
	if pile != null:
		remove_pile(pile)
	return pile


# --- Piles ---

func add_pile(kind: Pile.Kind, tile: Vector2i, capacity: int) -> Pile:
	var pile := Pile.new()
	pile.kind = kind
	pile.tile = tile
	pile.capacity = capacity
	piles.append(pile)
	return pile


## Puts a pile back from a save, contents and all. Nothing is reserved.
func restore_pile(kind: Pile.Kind, tile: Vector2i, capacity: int, only_type: int, counts: Dictionary) -> Pile:
	var pile: Pile = add_pile(kind, tile, capacity)
	pile.only_type = only_type
	for type: int in counts:
		var count: int = counts[type]
		pile.counts[type] = count
		pile.units_used += count * _sizes[type]
		totals[type] += count
	if kind == Pile.Kind.STOCKPILE:
		_stock_piles[tile] = pile
	changed.emit()
	return pile


## Takes a pile out of storage. Its counts are left intact for spilling.
func remove_pile(pile: Pile) -> void:
	if pile.removed:
		return
	pile.removed = true
	piles.erase(pile)
	if pile.kind == Pile.Kind.STOCKPILE:
		_stock_piles.erase(pile.tile)
	for type: int in pile.counts:
		totals[type] -= pile.counts[type]
	changed.emit()


## Puts an item straight into a pile, with no reservation. False if it doesn't fit.
func put(pile: Pile, type: int) -> bool:
	if pile.removed or not pile.accepts(type) or pile.free_units() < _sizes[type]:
		return false
	_add(pile, type)
	return true


# --- Bringing items in ---

## Claims room for one item in the stockpile: a matching pile with space if one
## can be reached, otherwise a new pile on a free stockpile tile. Null when
## there is no room.
func reserve_stock_space(type: int, near: Vector2i, flood_map: FloodMap) -> Pile:
	var size: int = _sizes[type]
	var best: Pile = null
	var best_score: int = 0
	for pile: Pile in _stock_piles.values():
		if pile.only_type != type or pile.free_units() < size:
			continue
		if Pathfinder.best_access(flood_map, pile.tile.x, pile.tile.y, true) == Pathfinder.NO_SPOT:
			continue
		var score: int = _manhattan(pile.tile, near)
		if best == null or score < best_score:
			best = pile
			best_score = score
	if best == null:
		var best_tile := Pathfinder.NO_SPOT
		for tile: Vector2i in _stock_tiles:
			if _stock_piles.has(tile):
				continue
			if Pathfinder.best_access(flood_map, tile.x, tile.y, true) == Pathfinder.NO_SPOT:
				continue
			var score: int = _manhattan(tile, near)
			if best_tile == Pathfinder.NO_SPOT or score < best_score:
				best_tile = tile
				best_score = score
		if best_tile == Pathfinder.NO_SPOT:
			return null
		best = add_pile(Pile.Kind.STOCKPILE, best_tile, _stockpile_capacity)
		best.only_type = type
		_stock_piles[best_tile] = best
	best.units_reserved += size
	return best


## Gives back space reserved for an item that won't arrive.
func release_space(pile: Pile, type: int) -> void:
	pile.units_reserved = maxi(pile.units_reserved - _sizes[type], 0)
	_drop_if_empty(pile)


## Adds an item whose space was reserved.
func deposit(pile: Pile, type: int) -> void:
	pile.units_reserved = maxi(pile.units_reserved - _sizes[type], 0)
	_add(pile, type)


# --- Taking items out ---

## Nearest reachable pile with one of this type to spare, or null.
func find_source(type: int, flood_map: FloodMap) -> Pile:
	var best: Pile = null
	var best_dist: int = 0
	for pile: Pile in piles:
		if pile.available(type) <= 0:
			continue
		var spot: Vector2i = Pathfinder.best_access(flood_map, pile.tile.x, pile.tile.y, true)
		if spot == Pathfinder.NO_SPOT:
			continue
		var dist: int = flood_map.distance_to(spot.x, spot.y)
		if best == null or dist < best_dist:
			best = pile
			best_dist = dist
	return best


## Items of a type sitting in piles and not promised to anyone.
func available_total(type: int) -> int:
	var total: int = 0
	for pile: Pile in piles:
		total += maxi(pile.available(type), 0)
	return total


## Promises one item to a hauler who is on the way to collect it.
func reserve_out(pile: Pile, type: int) -> void:
	pile.reserved_out[type] = pile.reserved_out.get(type, 0) + 1


func release_out(pile: Pile, type: int) -> void:
	pile.reserved_out[type] = maxi(pile.reserved_out.get(type, 0) - 1, 0)


## Removes one promised item from the pile. False if it is no longer there.
func take(pile: Pile, type: int) -> bool:
	release_out(pile, type)
	if pile.removed or pile.count_of(type) <= 0:
		return false
	pile.counts[type] -= 1
	if pile.counts[type] == 0:
		pile.counts.erase(type)
	pile.units_used -= _sizes[type]
	totals[type] -= 1
	if not _drop_if_empty(pile):
		changed.emit()
	return true


func _add(pile: Pile, type: int) -> void:
	pile.counts[type] = pile.count_of(type) + 1
	pile.units_used += _sizes[type]
	totals[type] += 1
	changed.emit()


## An empty stockpile pile gives its tile back, so another type can use it.
func _drop_if_empty(pile: Pile) -> bool:
	if pile.kind != Pile.Kind.STOCKPILE or pile.removed or not pile.is_empty():
		return false
	remove_pile(pile)
	return true


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
