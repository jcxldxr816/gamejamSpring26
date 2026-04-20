# SecurityCamera.gd
# Attach to a Node3D. Pans idle, detects player in cone, feeds HeatManager.
#
# Scene structure:
#   Node3D              "SecurityCamera" — this script
#     MeshInstance3D    "CameraMesh"     — visible camera body (any mesh)
#     SpotLight3D       "ConeLight"      — visualises the detection cone in the world
#     Area3D            "DetectionArea"  — rough sphere for initial proximity check
#       CollisionShape3D                 — SphereShape3D, radius = detection_range
#
# The cone is approximated: Area3D catches anything within detection_range,
# then a dot product check confirms the body is within fov_angle of the
# camera's forward direction. This gives accurate cone behaviour without
# a frustum shape.
#
# Add each SecurityCamera instance to the "security_cameras" group.

class_name SecurityCamera
extends Node3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## Half-angle of the detection cone in degrees. 35 = fairly narrow.
@export_range(5.0, 90.0) var fov_angle: float = 35.0

## How far the cone reaches in metres.
@export var detection_range: float = 10.0

## Heat added per second while the player is in view.
@export var heat_rate: float = 5.0

## Degrees per second the camera pans left and right while idle.
@export var pan_speed: float = 25.0

## Total degrees it pans each direction from its rest rotation.
@export var pan_range: float = 45.0

## How much faster the camera pans when alert (tracking the player).
@export var alert_pan_speed: float = 10.0

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var detection_area: Area3D = $DetectionArea
@onready var cone_light: SpotLight3D = $ConeLight

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum State { IDLE, ALERT }
var _state: State = State.IDLE

var _player_in_area: bool = false
var _player_node: Node3D = null

## Unique id for registering with HeatManager.
var _source_id: String = ""

## Pan direction: 1 = right, -1 = left.
var _pan_dir: float = 1.0

## Accumulated pan offset from rest rotation in degrees.
var _pan_offset: float = 0.0

## Rest Y rotation (world space) captured in _ready.
var _rest_rotation_y: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_source_id = "camera_" + str(get_path())
	_rest_rotation_y = rotation.y
	print("SecurityCamera ready, detection_area: ", detection_area)
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)
		print("camera signals connected")
	else:
		print("detection_area NOT found — check node is named exactly 'DetectionArea'")

	# Size the collision sphere to match detection_range.
	var shape_node := detection_area.get_child(0) as CollisionShape3D
	if shape_node and shape_node.shape is SphereShape3D:
		(shape_node.shape as SphereShape3D).radius = detection_range -5.0

	# Configure the spotlight to visually match the cone.
	if cone_light:
		cone_light.spot_range = detection_range
		cone_light.spot_angle = fov_angle
		cone_light.light_color = Color(1.0, 0.95, 0.7)   # warm idle colour
		cone_light.light_energy = 100.5

func _process(delta: float) -> void:
	_update_pan(delta)
	_update_detection()

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

func _update_detection() -> void:
	if not _player_in_area or _player_node == null:
		_set_state(State.IDLE)
		return
	#print("player in area, cone check: ", _is_player_in_cone())
	if _is_player_in_cone():
		_set_state(State.ALERT)
	else:
		_set_state(State.IDLE)

func _is_player_in_cone() -> bool:
	var to_player := (_player_node.global_position - global_position).normalized()
	# Camera forward is -Z in Godot's coordinate system.
	var forward := global_transform.basis.x.normalized()
	var dot := forward.dot(to_player)
	var angle := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
	#print()
	#print("to_player: ", to_player.snapped(Vector3.ONE * 0.01))
	#print("+X: ", global_transform.basis.x.snapped(Vector3.ONE * 0.01))
	#print("-X: ", (-global_transform.basis.x).snapped(Vector3.ONE * 0.01))
	#print("+Z: ", global_transform.basis.z.snapped(Vector3.ONE * 0.01))
	#print("-Z: ", (-global_transform.basis.z).snapped(Vector3.ONE * 0.01))
	return angle <= fov_angle

# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == _state:
		return
	_state = new_state
	#print("camera state changed to: ", _state)
	match _state:
		State.IDLE:
			#print("removing heat source: ", _source_id)
			HeatManager.remove_source(_source_id)
			if cone_light:
				cone_light.light_color = Color(1.0, 0.95, 0.7)
				cone_light.light_energy = 15.0
		State.ALERT:
			#print("adding heat source: ", _source_id, " rate: ", heat_rate)
			HeatManager.add_source(_source_id, heat_rate)
			if cone_light:
				cone_light.light_color = Color(1.0, 0.2, 0.1)   # red when alert
				cone_light.light_energy = 30.0

# ---------------------------------------------------------------------------
# Panning
# ---------------------------------------------------------------------------

func _update_pan(delta: float) -> void:
	var speed := alert_pan_speed if _state == State.ALERT else pan_speed

	_pan_offset += speed * _pan_dir * delta

	if _pan_offset >= pan_range:
		_pan_offset = pan_range
		_pan_dir = -1.0
	elif _pan_offset <= -pan_range:
		_pan_offset = -pan_range
		_pan_dir = 1.0

	rotation.y = _rest_rotation_y + deg_to_rad(_pan_offset)

# ---------------------------------------------------------------------------
# Area callbacks
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	print("camera sees body: ", body.name, " player: ", body.is_in_group("player"))
	if body.is_in_group("player"):
		_player_in_area = true
		_player_node = body

func _on_body_exited(body: Node3D) -> void:
	print("camera lost body: ", body.name)
	if body.is_in_group("player"):
		_player_in_area = false
		_player_node = null
		_set_state(State.IDLE)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _exit_tree() -> void:
	HeatManager.remove_source(_source_id)
