# TaggingUI.gd
# Attach to a CanvasLayer > Control scene that overlays the 3D world.
#
# Expected scene structure:
#   CanvasLayer
#     TaggingUI  (this script, root Control node)
#       Panel
#         VBoxContainer
#           Label (id: StepLabel)        -- "Step 1 of 3"
#           HBoxContainer (id: OptionsRow)
#             -- four OptionSlot children built at runtime (see below)
#           Label (id: SignatureLabel)   -- shows chosen layers so far
#
# Each OptionSlot is a VBoxContainer containing:
#   TextureRect (id: Icon)
#   Label (id: OptionLabel)
#   Label (id: ButtonHint)  -- "A", "B", "X", "Y"
#
# You can build this manually or let _build_ui() scaffold it at runtime
# (prototype mode — set PROTOTYPE_MODE = true).

extends Control

const BUTTON_HINTS := ["A", "B", "X", "Y"]
const PROTOTYPE_MODE := true   # Set false when you have a real scene built

# Node references — set in _ready if PROTOTYPE_MODE, otherwise use @onready vars.
var _step_label: Label
var _options_row: HBoxContainer
var _signature_label: Label
var _option_slots: Array = []   # Array of Dictionaries {icon, name_label, hint_label}

# Tracks which option is highlighted for controller navigation.
var _highlighted_index: int = 0

# Current options being displayed.
var _current_options: Array = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if PROTOTYPE_MODE:
		_build_ui()
	hide()
	_connect_signals()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Face button picks (A/B/X/Y mapped to ui_accept/ui_cancel/face_x/face_y).
	# In your project InputMap, define:
	#   "tag_pick_0" -> Joypad Button 0 (A / Cross)
	#   "tag_pick_1" -> Joypad Button 1 (B / Circle)
	#   "tag_pick_2" -> Joypad Button 2 (X / Square)
	#   "tag_pick_3" -> Joypad Button 3 (Y / Triangle)
	#   "tag_cancel"  -> Joypad Button 1 held, or Escape
	# Keyboard fallback: 1/2/3/4 keys and Escape.
	for i in 4:
		if event.is_action_pressed("tag_pick_%d" % i):
			_on_option_chosen(i)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("tag_cancel"):
		if visible:
			TaggingManager.cancel_creation()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Signal connections
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	TaggingManager.creation_started.connect(_on_creation_started)
	TaggingManager.step_advanced.connect(_on_step_advanced)
	TaggingManager.creation_finished.connect(_on_creation_finished)
	TaggingManager.creation_cancelled.connect(_on_creation_cancelled)
	TaggingManager.tag_placed.connect(_on_tag_placed)

# ---------------------------------------------------------------------------
# TaggingManager signal handlers
# ---------------------------------------------------------------------------

func _on_creation_started(options: Array) -> void:
	_current_options = options
	_highlighted_index = 0
	_update_step_label(1)
	_update_signature("")
	_populate_options(options)
	show()

func _on_step_advanced(step: int, options: Array) -> void:
	_current_options = options
	_highlighted_index = 0
	_update_step_label(step + 1)
	_update_signature(_build_signature_text())
	_populate_options(options)

func _on_creation_finished(design: TagDesign) -> void:
	# Keep the UI visible but switch to a "confirm placement" state.
	# The player now aims at the TagSpot and presses tag_pick_0 to confirm.
	_update_step_label(-1)   # -1 signals "placement mode" to _update_step_label
	_update_signature(_build_signature_text_from_design(design))
	_clear_options()

func _on_creation_cancelled() -> void:
	print("UI received cancellation, hiding")
	hide()

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _on_option_chosen(index: int) -> void:
	if index >= _current_options.size():
		return
	_highlighted_index = index
	_refresh_highlight()
	TaggingManager.confirm_choice(index)

func _update_step_label(step: int) -> void:
	if _step_label == null:
		return
	if step == -1:
		_step_label.text = "Aim at surface — press T to place"
	else:
		_step_label.text = "Step %d of %d" % [step, TaggingManager.step_count]

func _update_signature(text: String) -> void:
	if _signature_label:
		_signature_label.text = text

func _on_tag_placed(design: TagDesign) -> void:
	hide()

func _populate_options(options: Array) -> void:
	for i in 4:
		if i >= _option_slots.size():
			break
		var slot: Dictionary = _option_slots[i]
		var layer: TagLayer = options[i] if i < options.size() else null
		if layer:
			slot["name_label"].text = layer.label
			if slot.has("icon") and layer.preview_texture:
				slot["icon"].texture = layer.preview_texture
			else: 
				if slot.has("icon"):
					slot["icon"].texture = null
		else:
			slot["name_label"].text = "—"
	_refresh_highlight()

func _clear_options() -> void:
	for slot in _option_slots:
		slot["name_label"].text = ""
		if slot.has("icon"):
			slot["icon"].texture = null

func _refresh_highlight() -> void:
	for i in _option_slots.size():
		var slot: Dictionary = _option_slots[i]
		if slot.has("container"):
			var c: Control = slot["container"]
			# Simple highlight: modulate the selected slot brighter.
			c.modulate = Color(1.4, 1.4, 0.4) if i == _highlighted_index else Color.WHITE

func _build_signature_text() -> String:
	# Build from the TaggingManager's in-progress design.
	# We reconstruct from what the UI knows about chosen options.
	return ""   # Filled in once we have a reference to the design.

func _build_signature_text_from_design(design: TagDesign) -> String:
	var parts: Array[String] = []
	for layer in design.chosen_layers:
		parts.append(layer.label)
	return " + ".join(parts)

# ---------------------------------------------------------------------------
# Prototype UI scaffolding
# Builds a minimal but functional layout entirely in code so you don't need
# a .tscn file while iterating. Replace with a proper scene when ready.
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -300
	offset_right = 300
	offset_top = -220
	offset_bottom = -20

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_step_label)

	_options_row = HBoxContainer.new()
	_options_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_options_row.add_theme_constant_override("separation", 16)
	_options_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_options_row)

	for i in 4:
		var slot_container := VBoxContainer.new()
		slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
		_options_row.add_child(slot_container)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_container.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		slot_container.add_child(name_lbl)

		var hint_lbl := Label.new()
		hint_lbl.text = BUTTON_HINTS[i]
		hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_lbl.add_theme_font_size_override("font_size", 12)
		hint_lbl.modulate = Color(0.7, 0.7, 0.7)
		slot_container.add_child(hint_lbl)

		_option_slots.append({
			"container": slot_container,
			"icon": icon,
			"name_label": name_lbl,
			"hint_label": hint_lbl,
		})

	_signature_label = Label.new()
	_signature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_signature_label.add_theme_font_size_override("font_size", 13)
	_signature_label.modulate = Color(0.9, 0.9, 0.5)
	vbox.add_child(_signature_label)
