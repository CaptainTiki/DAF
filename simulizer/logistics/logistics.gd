class_name Logistics
extends RefCounted
## The list of open requests for items. Whoever owns a request (a build site,
## a station) creates it here, watches it fill, and closes it when done.

var requests: Array[Request] = []


func add(tile: Vector2i, item_type: int, count: int, purpose: String) -> Request:
	var request := Request.new()
	request.tile = tile
	request.item_type = item_type
	request.wanted = count
	request.purpose = purpose
	requests.append(request)
	return request


## Ends a request, whether it was used up or cancelled. Haulers already on the
## way notice and drop what they carry.
func close(request: Request) -> void:
	request.closed = true
	requests.erase(request)


## Items still needing a hauler, across all requests.
func open_count() -> int:
	var total: int = 0
	for request: Request in requests:
		total += request.open_count()
	return total


func open_count_of(item_type: int) -> int:
	var total: int = 0
	for request: Request in requests:
		if request.item_type == item_type:
			total += request.open_count()
	return total
