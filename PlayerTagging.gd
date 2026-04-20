# PlayerTagging.gd
# Add this as a child of your Player node. It does not touch movement.
#
# This component:
#   - Tracks which TagSpot(s) the player is currently near
#   - Handles the "initiate tag" input and delegates to TaggingManager
#   - Handles the "confirm placement" input after design is complete
#   - Feeds into the heat system later via signals

extends Node

# ---------------------------------------------------------------------------
# Signals (for the heat/record system to connect to later)
# ---------------------------------------------------------------------------

## Player started a tagging action at a spot.
signal tagging_started(spot: TagSpot)

## Player successfully placed a tag.
signal tag_placed(design: TagDesign, spot: TagSpot)

## Player cancelled mid-tag.
signal tagging_cancelled()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## TagSpots currently in player proximity (populated by TagSpot signals or
## by detecting which spots are nearby via group query).
var _nearby_spots: Array[TagSpot] = []

## The spot we're currently in the process of tagging.
var _active_spot: TagSpot = null

## The finished design waiting for the player to confirm placement.
var _pending_design: TagDesign = null

var _is_designing: bool = false
var _awaiting_placement: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	TaggingManager.creation_finished.connect(_on_design_finished)
	TaggingManager.creation_cancelled.connect(_on_cancelled)
	var spots = get_tree().get_nodes_in_group("tag_spots")
	print("found tag_spots: ", spots.size())
	for spot in spots:
		spot.player_proximity_changed.connect(func(in_range): register_nearby_spot(spot, in_range))

func _unhandled_input(event: InputEvent) -> void:
	# "tag_initiate" — start tagging or confirm placement.
	# Suggested mapping: Joypad Button 4 (LB/L1) or keyboard T.
	if event.is_action_pressed("tag_initiate"):
		_handle_initiate_or_confirm()
		return

	# "tag_cancel" is handled by TaggingUI, but we also need to clean up here.
	if event.is_action_pressed("tag_cancel"):
		if _is_designing or _awaiting_placement:
			_cleanup()

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------

func _handle_initiate_or_confirm() -> void:
	if _awaiting_placement:
		# Design is done — confirm placement at the nearest valid spot.
		_try_confirm_placement()
		return

	if _is_designing:
		# Already in the picker, ignore.
		return

	# Find the best nearby spot and start designing.
	var spot := _get_best_nearby_spot()
	if spot == null:
		return

	_active_spot = spot
	_is_designing = true
	tagging_started.emit(spot)
	TaggingManager.start_creation()

func _try_confirm_placement() -> void:
	if _active_spot == null or _pending_design == null:
		_cleanup()
		return

	var success := _active_spot.confirm_placement()
	if success:
		tag_placed.emit(_pending_design, _active_spot)
	_cleanup()

# ---------------------------------------------------------------------------
# TaggingManager callbacks
# ---------------------------------------------------------------------------

func _on_design_finished(design: TagDesign) -> void:
	_pending_design = design
	_is_designing = false
	_awaiting_placement = true
	# TaggingUI now shows "aim and press A to place" prompt.

func _on_cancelled() -> void:
	_cleanup()
	tagging_cancelled.emit()

# ---------------------------------------------------------------------------
# TagSpot proximity tracking
# ---------------------------------------------------------------------------

## Call this from your TagSpot.player_proximity_changed signal,
## or wire it up via groups. TagSpot emits player_proximity_changed(in_range).
func register_nearby_spot(spot: TagSpot, in_range: bool) -> void:
	print("register_nearby_spot called: ", spot.name, " in_range: ", in_range)
	if in_range:
		if not _nearby_spots.has(spot):
			_nearby_spots.append(spot)
	else:
		_nearby_spots.erase(spot)
		if _active_spot == spot and (_is_designing or _awaiting_placement):
			TaggingManager.cancel_creation()

## Returns the closest untagged spot, or null if none are nearby.
func _get_best_nearby_spot() -> TagSpot:
	var best: TagSpot = null
	var best_dist: float = INF
	var player_pos: Vector3 = get_parent().global_position
	for spot in _nearby_spots:
		if spot.is_tagged:
			continue
		var d := player_pos.distance_to(spot.global_position)
		if d < best_dist:
			best_dist = d
			best = spot
	return best

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _cleanup() -> void:
	_active_spot = null
	_pending_design = null
	_is_designing = false
	_awaiting_placement = false


func _on_tag_spot_player_proximity_changed(in_range: bool) -> void:
	pass # Replace with function body.
