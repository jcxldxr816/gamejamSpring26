# HeatBar.gd
# Attach to a Control node inside a CanvasLayer.
# Builds its own UI in code — no .tscn needed.
#
# Scene structure (all built in code):
#   CanvasLayer
#     Control   <- HeatBar.gd (this script)
#
# Displays a horizontal bar in the top-right corner.
# Green -> yellow -> red as heat climbs.
# Flashes red when player is caught.

extends Control

# ---------------------------------------------------------------------------
# Node references (built in code)
# ---------------------------------------------------------------------------

var _bar: ColorRect
var _background: ColorRect
var _label: Label
var _caught_flash: ColorRect

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

const BAR_WIDTH := 200.0
const BAR_HEIGHT := 18.0
const MARGIN := 16.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	HeatManager.heat_changed.connect(_on_heat_changed)
	HeatManager.player_caught.connect(_on_player_caught)
	HeatManager.heat_reset.connect(_on_heat_reset)

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_heat_changed(value: float) -> void:
	var t := value / 100.0
	_bar.size.x = BAR_WIDTH * t
	_bar.color = Color(t * 1.0, (1.0 - t) * 0.85, 0.05)
	_label.text = "HEAT  %d%%" % int(value)

func _on_player_caught() -> void:
	_caught_flash.show()
	_label.text = "CAUGHT"
	_label.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(_caught_flash, "modulate:a", 0.0, 1.2)
	tween.tween_callback(_caught_flash.hide)

func _on_heat_reset() -> void:
	_caught_flash.hide()
	_caught_flash.modulate.a = 0.8

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Anchor to top-right.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(BAR_WIDTH + MARGIN * 2 + 8)
	offset_top = MARGIN
	offset_right = -MARGIN
	offset_bottom = MARGIN + BAR_HEIGHT + 20

	# Background track.
	_background = ColorRect.new()
	_background.color = Color(0.08, 0.08, 0.08, 0.85)
	_background.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_background.position = Vector2(0, 18)
	add_child(_background)

	# Filled bar.
	_bar = ColorRect.new()
	_bar.color = Color(0.1, 0.85, 0.05)
	_bar.size = Vector2(0, BAR_HEIGHT)
	_bar.position = Vector2(0, 18)
	add_child(_bar)

	# Label above the bar.
	_label = Label.new()
	_label.text = "HEAT  0%"
	_label.add_theme_font_size_override("font_size", 13)
	_label.position = Vector2(0, 0)
	_label.size = Vector2(BAR_WIDTH, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_label)

	# Full-screen red flash on caught.
	_caught_flash = ColorRect.new()
	_caught_flash.color = Color(1.0, 0.0, 0.0, 0.8)
	_caught_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Needs to cover the whole screen — reparent to a full-rect control.
	# We achieve this by making it very large and offset from top-right anchor.
	_caught_flash.position = Vector2(-2000, -2000)
	_caught_flash.size = Vector2(4000, 4000)
	_caught_flash.hide()
	add_child(_caught_flash)
