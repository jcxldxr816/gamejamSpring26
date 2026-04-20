# TaggingManager.gd
# Autoload singleton. Add this to Project > Project Settings > Autoload as "TaggingManager".
#
# Responsibilities:
#   - Holds all TagLayer definitions organised by step index
#   - Drives the tag creation state machine
#   - Emits signals the UI and PlayerTagging component listen to
#   - Stores the list of all placed TagDesigns (feeds into the record system later)
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player starts a new tag creation session.
## `options` is an Array[TagLayer] of four choices for step 0.
signal creation_started(options: Array)

## Emitted each time the player confirms a choice and moves to the next step.
## `step` is the new step index, `options` is the next Array[TagLayer] of four.
signal step_advanced(step: int, options: Array)

## Emitted when all steps are complete and a TagDesign has been built.
signal creation_finished(design: TagDesign)

## Emitted when the player cancels mid-flow.
signal creation_cancelled()

## Emitted after a TagDesign has been committed to a TagSpot in the world.
signal tag_placed(design: TagDesign)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

## How many steps the creation flow has. Each step picks one layer.
## Keep this at 3 for the prototype — matches the A/B/X/Y × 3 steps spec.
@export var step_count: int = 3

## Layer pools per step. Populate these in the editor or via _ready().
## Each inner array should have at least 4 TagLayer resources.
## layers_by_step[0] = pool for step 1, [1] = pool for step 2, etc.
@export var layers_by_step: Array = []   # Array[Array[TagLayer]]

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _active: bool = false
var _current_step: int = 0
var _current_design: TagDesign = null
var _placed_designs: Array[TagDesign] = []

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Begin a new tag creation session. Called by PlayerTagging when the player
## initiates tagging at a valid TagSpot.
func start_creation() -> void:
	if _active:
		return
	_active = true
	_current_step = 0
	_current_design = TagDesign.new()
	var options := _get_options_for_step(_current_step)
	creation_started.emit(options)

## Confirm a choice for the current step.
## `choice_index` is 0-3 corresponding to A/B/X/Y.
func confirm_choice(choice_index: int) -> void:
	if not _active:
		return
	var options := _get_options_for_step(_current_step)
	if choice_index < 0 or choice_index >= options.size():
		push_warning("TaggingManager: choice_index %d out of range" % choice_index)
		return

	var chosen: TagLayer = options[choice_index]
	_current_design.chosen_layers.append(chosen)
	_current_step += 1

	if _current_step >= step_count:
		_finish_creation()
	else:
		var next_options := _get_options_for_step(_current_step)
		step_advanced.emit(_current_step, next_options)

## Cancel the current creation session without placing a tag.
func cancel_creation() -> void:
	_active = false
	_current_design = null
	creation_cancelled.emit()

## Called by a TagSpot after it has applied the decal to the world.
## Finalises the design record and notifies listeners.
func commit_design(design: TagDesign, world_pos: Vector3) -> void:
	design.world_position = world_pos
	_placed_designs.append(design)
	_active = false
	tag_placed.emit(design)

## Returns a copy of all placed designs (for the record system).
func get_all_placed_designs() -> Array[TagDesign]:
	return _placed_designs.duplicate()

## Whether a creation session is currently in progress.
func is_active() -> bool:
	return _active

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _ready() -> void:
	# If no layers were configured in the editor, generate placeholder pools
	# so the system works immediately in the prototype.
	if layers_by_step.is_empty():
		_build_placeholder_layers()

func _get_options_for_step(step: int) -> Array:
	if step >= layers_by_step.size():
		push_error("TaggingManager: no layer pool for step %d" % step)
		return []
	var pool: Array = layers_by_step[step]
	if pool.size() < 4:
		push_warning("TaggingManager: step %d pool has fewer than 4 options" % step)
	# Always return exactly 4 options, cycling if the pool is small.
	var result: Array = []
	for i in 4:
		result.append(pool[i % pool.size()])
	return result

func _finish_creation() -> void:
	creation_finished.emit(_current_design)
	# Note: _active stays true until commit_design() is called.
	# PlayerTagging holds the design and waits for the player to confirm
	# placement at the TagSpot before calling commit_design().

## Generates simple placeholder TagLayer resources so you can test the flow
## without any art assets. Replace with real resources when art is ready.
##
## Each option within a step gets a distinct color. The player is picking a
## color per layer — the icon.svg shape is the same for all, but the tint
## and rotation (handled in TagSpot) make each layer visually distinct.
func _build_placeholder_layers() -> void:
	# Four color choices per step. Steps use different hue families so the
	# three composited layers read as clearly separate on the wall.
	var color_sets := [
		# Step 1 — warm reds/oranges
		[Color(1.0, 0.15, 0.15), Color(1.0, 0.5, 0.0), Color(1.0, 0.85, 0.0), Color(0.8, 0.0, 0.3)],
		# Step 2 — cool blues/greens
		[Color(0.0, 0.6, 1.0), Color(0.0, 1.0, 0.6), Color(0.3, 0.0, 1.0), Color(0.0, 0.9, 0.9)],
		# Step 3 — purples/pinks
		[Color(0.8, 0.0, 1.0), Color(1.0, 0.0, 0.6), Color(0.6, 0.4, 1.0), Color(1.0, 0.4, 0.8)],
	]
	var label_sets := [
		["Red", "Orange", "Yellow", "Crimson"],
		["Blue", "Green", "Violet", "Cyan"],
		["Purple", "Pink", "Lavender", "Rose"],
	]
	for step_idx in step_count:
		var pool: Array = []
		var colors: Array = color_sets[step_idx % color_sets.size()]
		var labels: Array = label_sets[step_idx % label_sets.size()]
		for i in 4:
			var layer := TagLayer.new()
			layer.label = labels[i]
			layer.tint = colors[i]
			layer.category = "base" if step_idx == 0 else ("fill" if step_idx == 1 else "accent")
			pool.append(layer)
		layers_by_step.append(pool)
