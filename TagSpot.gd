# TagSpot.gd
# Attach to a Node3D in the world to mark it as a taggable location.
#
# Scene structure:
#   Node3D  (TagSpot.gd)
#     Area3D          "ProximityArea"  with CollisionShape3D
#     Decal           "TagDecal"       positioned flush against the wall
#     Node3D          "PromptIndicator"
#
# No art assets needed. Uses res://icon.svg (standard Godot project file).
# Each layer of the design renders the icon in a different color, rotated,
# at 25% opacity. All layers are composited into a single ImageTexture
# and applied to the Decal.

class_name TagSpot
extends Node3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal tagged(design: TagDesign)
signal player_proximity_changed(in_range: bool)

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export_range(0.0, 1.0) var visibility_rating: float = 0.5
@export var location_tags: Array[String] = []

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var is_tagged: bool = false
var placed_design: TagDesign = null

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var proximity_area: Area3D = $ProximityArea
@onready var tag_decal: Decal = $TagDecal
@onready var prompt_indicator: Node3D = $PromptIndicator

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

var _player_in_range: bool = false
var _pending_design: TagDesign = null

# Rotation offsets per layer so they don't stack identically.
const LAYER_ROTATIONS := [0.0, 25.0, -15.0]

# Canvas resolution for the composited tag image.
const CANVAS_SIZE := 256

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if proximity_area:
		proximity_area.body_entered.connect(_on_body_entered)
		proximity_area.body_exited.connect(_on_body_exited)

	if tag_decal:
		tag_decal.hide()
		#tag_decal.position.y + 0.5
		tag_decal.rotation_degrees.x = 90.0

	if prompt_indicator:
		prompt_indicator.hide()

	TaggingManager.creation_finished.connect(_on_design_ready)
	TaggingManager.creation_cancelled.connect(_on_creation_cancelled)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func is_player_in_range() -> bool:
	return _player_in_range

func apply_tag(design: TagDesign) -> void:
	if is_tagged:
		return
	is_tagged = true
	placed_design = design
	design.spot_path = get_path()

	_apply_decal(design)
	TaggingManager.commit_design(design, global_position)

	if prompt_indicator:
		prompt_indicator.hide()

	tagged.emit(design)

func remove_tag() -> void:
	is_tagged = false
	placed_design = null
	if tag_decal:
		tag_decal.texture_albedo = null
		tag_decal.hide()

func confirm_placement() -> bool:
	if _pending_design == null or not _player_in_range or is_tagged:
		return false
	apply_tag(_pending_design)
	_pending_design = null
	return true

# ---------------------------------------------------------------------------
# Proximity callbacks
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	print("body entered: ", body.name, " groups: ", body.get_groups())
	if body.is_in_group("player"):
		print("player detected, emitting proximity signal")
		_player_in_range = true
		if not is_tagged and prompt_indicator:
			prompt_indicator.show()
		player_proximity_changed.emit(true)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if prompt_indicator:
			prompt_indicator.hide()
		player_proximity_changed.emit(false)
		if TaggingManager.is_active():
			TaggingManager.cancel_creation()

# ---------------------------------------------------------------------------
# Design placement callbacks
# ---------------------------------------------------------------------------

func _on_design_ready(design: TagDesign) -> void:
	if not _player_in_range or is_tagged:
		return
	_pending_design = design

func _on_creation_cancelled() -> void:
	_pending_design = null

# ---------------------------------------------------------------------------
# Decal compositing
# ---------------------------------------------------------------------------

func _apply_decal(design: TagDesign) -> void:
	if tag_decal == null:
		return

	#var icon_paths := ["res://icon.svg", "res://smiley.png", "res://panda.png"]
	var icon_paths := ["res://smiley.png", "res://panda.png"]
	var icon: Texture2D = load(icon_paths[randi() % icon_paths.size()])
	if icon == null:
		push_warning("TagSpot: could not load res://icon.svg")
		tag_decal.show()
		return

	# Start with a fully transparent canvas.
	var base := Image.create(CANVAS_SIZE, CANVAS_SIZE, true, Image.FORMAT_RGBA8)
	base.fill(Color(0, 0, 0, 0))

	var layer_count := design.chosen_layers.size()
	for i in layer_count:
		var layer: TagLayer = design.chosen_layers[i]
		var layer_img := _render_icon_layer(icon, layer.tint, i)
		_blend_over(base, layer_img)

	tag_decal.texture_albedo = ImageTexture.create_from_image(base)
	tag_decal.show()
	print("applying decal, layer count: ", design.chosen_layers.size())
	for i in design.chosen_layers.size():
		print("  layer ", i, " label: ", design.chosen_layers[i].label, " tint: ", design.chosen_layers[i].tint)

## Renders icon.svg tinted, rotated, and at 25% opacity onto a transparent canvas.
func _render_icon_layer(icon: Texture2D, tint: Color, offset_index: int) -> Image:
	var size := CANVAS_SIZE
	var result := Image.create(size, size, true, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))

	var icon_img := icon.get_image()
	icon_img.convert(Image.FORMAT_RGBA8)
	icon_img.resize(size, size, Image.INTERPOLATE_LANCZOS)

	# Shift each layer by a small amount so they don't stack identically
	var offsets := [Vector2(0, 0), Vector2(8, -6), Vector2(-6, 8)]
	var offset: Vector2 = offsets[offset_index % offsets.size()]

	for y in size:
		for x in size:
			var src_x := x - int(offset.x)
			var src_y := y - int(offset.y)
			if src_x < 0 or src_x >= size or src_y < 0 or src_y >= size:
				continue
			var src_color := icon_img.get_pixel(src_x, src_y)
			if src_color.a < 0.01:
				continue
			result.set_pixel(x, y, Color(
				src_color.r * tint.r,
				src_color.g * tint.g,
				src_color.b * tint.b,
				src_color.a * 0.5
			))

	return result

## Alpha-composite src over dst in place (Porter-Duff "over").
func _blend_over(dst: Image, src: Image) -> void:
	var size := dst.get_width()
	for y in size:
		for x in size:
			var s := src.get_pixel(x, y)
			if s.a < 0.001:
				continue
			var d := dst.get_pixel(x, y)
			var out_a := s.a + d.a * (1.0 - s.a)
			if out_a < 0.001:
				continue
			var out_r := (s.r * s.a + d.r * d.a * (1.0 - s.a)) / out_a
			var out_g := (s.g * s.a + d.g * d.a * (1.0 - s.a)) / out_a
			var out_b := (s.b * s.a + d.b * d.a * (1.0 - s.a)) / out_a
			dst.set_pixel(x, y, Color(out_r, out_g, out_b, out_a))
