class_name Job
extends RefCounted
## One unit of work. Claimed by at most one dwarf at a time.

enum Kind { DIG, HAUL, BUILD, CRAFT, HARVEST }

const KIND_COUNT: int = 5
const UNCLAIMED: int = -1

var id: int
var kind: Kind
## Where the work is: the tile to dig, the site, the station, the plant.
var tile: Vector2i
var claimed_by: int = UNCLAIMED
## Nobody takes this job before this tick. Set after a failed attempt.
var retry_tick: int = 0
## False once the job is finished or cancelled, and for one-off haul trips
## that were never listed.
var on_board: bool = false

## BUILD
var site: BuildSite
## CRAFT
var station: Station
## HARVEST
var plant: Plant

## HAUL: the item, once it exists as a loose or carried thing.
var item: Item
var item_type: int = -1
## HAUL: where to collect from, when the item is in a pile.
var source_pile: Pile
## HAUL: where it goes. Exactly one of these is set while the job is claimed.
var dest_pile: Pile
var dest_request: Request
## HAUL: true once the dwarf is carrying the item.
var picked_up: bool = false


func is_available(tick: int) -> bool:
	return on_board and claimed_by == UNCLAIMED and retry_tick <= tick
