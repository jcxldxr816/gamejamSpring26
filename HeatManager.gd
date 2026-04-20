# HeatManager.gd
# Autoload singleton. Add to Project > Project Settings > Autoload as "HeatManager".
#
# Owns the heat float and ticks it every frame based on registered heat sources.
# Cameras, tagging actions, and later enforcers register/unregister themselves
# as sources. HeatManager doesn't know what they are — just their rate per second.
#
# When heat hits 100 the player is caught:
#   - player_caught signal fires
#   - PlayerTagging removes the last placed tag
#   - Player is moved to the nearest DropPoint node in the scene
#   - Heat resets to 0

extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Fires every frame heat changes. UI listens to this.
signal heat_changed(value: float)

## Fires when heat hits 100.
signal player_caught()

## Fires when the caught sequence finishes and heat resets.
signal heat_reset()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

## How fast heat decays per second when no sources are active.
@export var decay_rate: float = 8.0

## Extra decay per second applied while the player is tagging
## and then cancels — reward for bailing quickly.
@export var cancel_bonus_decay: float = 12.0

## How many seconds the cancel bonus decay lasts after a cancel.
@export var cancel_bonus_duration: float = 3.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var heat: float = 0.0

## Active heat sources. Key = source id (string), value = rate per second.
var _sources: Dictionary = {}

var _cancel_bonus_timer: float = 0.0
var _caught: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _caught:
		return

	# Sum all active source rates.
	var total_rate: float = 0.0
	for rate in _sources.values():
		total_rate += rate

	if total_rate > 0.0:
		heat = minf(heat + total_rate * delta, 100.0)
	else:
		# Decay, with optional cancel bonus.
		var effective_decay := decay_rate
		if _cancel_bonus_timer > 0.0:
			effective_decay += cancel_bonus_decay
			_cancel_bonus_timer -= delta
		heat = maxf(heat - effective_decay * delta, 0.0)

	heat_changed.emit(heat)

	if heat >= 100.0:
		_trigger_caught()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Register a heat source. Call when a camera spots the player,
## tagging starts, etc. source_id should be unique per source (e.g. camera node path).
func add_source(source_id: String, rate_per_second: float) -> void:
	print("heat source added: ", source_id, " rate: ", rate_per_second, " total sources: ", _sources.size() + 1)
	_sources[source_id] = rate_per_second

## Remove a heat source. Call when camera loses sight, tagging ends, etc.
func remove_source(source_id: String) -> void:
	_sources.erase(source_id)

## Shortcut: remove all sources (e.g. on scene change).
func clear_sources() -> void:
	_sources.clear()

## Trigger the cancel bonus decay (call when player cancels mid-tag).
func notify_tagging_cancelled() -> void:
	_cancel_bonus_timer = cancel_bonus_duration

## Returns current heat 0-100.
func get_heat() -> float:
	return heat

## Returns true if any sources are currently active.
func is_under_observation() -> bool:
	return not _sources.is_empty()

# ---------------------------------------------------------------------------
# Caught sequence
# ---------------------------------------------------------------------------

func _trigger_caught() -> void:
	_caught = true
	_sources.clear()
	player_caught.emit()

	# Give listeners a frame to respond (remove tag, play animation, etc.)
	# before we reset and teleport.
	await get_tree().create_timer(1.5).timeout
	_finish_caught_sequence()

func _finish_caught_sequence() -> void:
	heat = 0.0
	_caught = false
	heat_reset.emit()
	heat_changed.emit(heat)

	# Find the nearest DropPoint in the scene and move the player there.
	var drop_points := get_tree().get_nodes_in_group("drop_points")
	if drop_points.is_empty():
		push_warning("HeatManager: no DropPoint nodes found in 'drop_points' group")
		return

	var player := _get_player()
	if player == null:
		return

	var nearest: Node3D = null
	var nearest_dist: float = INF
	for dp in drop_points:
		var d: float = player.global_position.distance_to((dp as Node3D).global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = dp

	if nearest:
		player.global_position = nearest.global_position

func _get_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as CharacterBody3D
