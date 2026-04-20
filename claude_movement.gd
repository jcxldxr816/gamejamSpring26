extends CharacterBody3D

# ─── Constants ────────────────────────────────────────────────────────────────
const JUMP_VELOCITY     : float = 10.0
const MOUSE_SENSITIVITY : float = 0.005

const FOV_DEFAULT: float = 75.0
const FOV_MAX: float = 120.0

const FORWARD_ACCEL  : float = 40.0   # acceleration while forward is held
var forward_decel  : float = 20.0  # deceleration when forward is released
const MAX_SPEED      : float = 50.0

const DASH_SPEED     : float = 24.0
const DASH_DURATION  : float = 0.1
const DASH_COOLDOWN  : float = 0.75
const POLL_WINDOW    : float = 0.05  # seconds to wait for diagonal input

const STOP_THRESHOLD : float = 0.5   # xz speed below this allows back dash
const DASH_INTERRUPT_SPEED : float = 5.0

# ─── State ────────────────────────────────────────────────────────────────────
enum State { IDLE, FORWARD, POLLING, DASH }
var state           : State   = State.IDLE

var dash_timer      : float   = 0.0  # counts down while dashing
var cooldown_timer  : float   = 0.0  # counts down after a dash
var poll_timer      : float   = 0.0  # counts down during poll window
var dash_velocity   : Vector3 = Vector3.ZERO

# Snap of input when poll started; updated during poll if diagonal arrives early
var poll_input      : Vector2 = Vector2.ZERO

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var spring_arm : SpringArm3D
@export var mesh       : MeshInstance3D
@export var camera: Camera3D

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _flat_basis() -> Basis:
	var cam_yaw := spring_arm.global_transform.basis.get_euler().y
	return Basis(Vector3.UP, cam_yaw)

func _xz_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func _start_dash(input_2d: Vector2) -> void:
	# input_2d is in camera-relative 2D space; convert to world direction
	var world_dir := (_flat_basis() * Vector3(input_2d.x, 0, input_2d.y)).normalized()
	dash_velocity  = world_dir * DASH_SPEED
	dash_timer     = DASH_DURATION
	cooldown_timer = DASH_COOLDOWN
	state          = State.DASH

# ─── Physics ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:

	# Gravity
	if not is_on_floor():
		var fall_multiplier := 2.5
		var low_jump_multiplier := 1.5
		if velocity.y < 0:
			velocity += get_gravity() * fall_multiplier * delta
		elif velocity.y > 0 and not Input.is_action_pressed("jump"):
			velocity += get_gravity() * low_jump_multiplier * delta
		else:
			velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Tick timers
	cooldown_timer = max(0.0, cooldown_timer - delta)

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var has_forward  : bool = input_dir.y < -0.1
	var has_backward : bool = input_dir.y >  0.1
	var has_side     : bool = abs(input_dir.x) > 0.1

	match state:

		# ── IDLE ──────────────────────────────────────────────────────────────
		State.IDLE:
			# Steer while coasting — rotate velocity direction with side input
			if has_side and _xz_speed() > STOP_THRESHOLD:
				var current_speed := _xz_speed()
				var current_dir := Vector3(velocity.x, 0, velocity.z).normalized()
				var cam_yaw := spring_arm.global_transform.basis.get_euler().y
				var flat := Basis(Vector3.UP, cam_yaw)
				var side_dir := (flat * Vector3(input_dir.x, 0, 0)).normalized()
				# Blend current travel direction with side input
				var side_steering_balance = 0.05
				var steered := (current_dir + side_dir * side_steering_balance).normalized()
				velocity.x = steered.x * current_speed
				velocity.z = steered.z * current_speed
				mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(steered.x, steered.z), 0.15)
			
			# Decelerate to stop
			velocity.x = move_toward(velocity.x, 0.0, forward_decel * delta)
			velocity.z = move_toward(velocity.z, 0.0, forward_decel * delta)

			if has_forward:
				state = State.FORWARD

			elif cooldown_timer <= 0.0:
				if (has_side or has_backward) and _xz_speed() < STOP_THRESHOLD:
					poll_input = input_dir
					poll_timer = POLL_WINDOW
					state      = State.POLLING

		# ── FORWARD ───────────────────────────────────────────────────────────
		State.FORWARD:
			var flat      := _flat_basis()
			var world_dir := (flat * Vector3(input_dir.x, 0, input_dir.y)).normalized()

			if has_forward:
				# Accelerate toward max speed in current look+steer direction
				var target := world_dir * MAX_SPEED
				velocity.x = move_toward(velocity.x, target.x, FORWARD_ACCEL * delta)
				velocity.z = move_toward(velocity.z, target.z, FORWARD_ACCEL * delta)

				# Rotate mesh to face movement direction
				if world_dir.length() > 0.1:
					mesh.rotation.y = lerp_angle(
						mesh.rotation.y,
						atan2(world_dir.x, world_dir.z),
						0.15
					)

				# Side dash only allowed below a speed threshold
				#if has_side and not has_backward and cooldown_timer <= 0.0 and _xz_speed() < DASH_INTERRUPT_SPEED:
					#_start_dash(Vector2(sign(input_dir.x), 0.0))
				if (has_side or has_backward) and cooldown_timer <= 0.0 and _xz_speed() < DASH_INTERRUPT_SPEED:
					poll_input = input_dir
					poll_timer = POLL_WINDOW
					state      = State.POLLING

			else:
				# Forward released — bleed off momentum
				state = State.IDLE

		# ── POLLING ───────────────────────────────────────────────────────────
		# Waiting briefly to see if a diagonal (back+side) was intended
		State.POLLING:
			poll_timer -= delta

			# Update polled input each frame so we catch side input immediately
			poll_input = input_dir

			# Early exit: side detected — fire diagonal dash now
			if has_side and has_backward:
				_start_dash(Vector2(input_dir.x, sign(input_dir.y)).normalized())

			# Poll window expired — fire with whatever input we have
			elif poll_timer <= 0.0:
				# Fire with accumulated input — side only, back only, or diagonal
				var dash_dir := Vector2(poll_input.x, max(poll_input.y, 0.0))
				if dash_dir.length() > 0.1:
					_start_dash(dash_dir.normalized())
				else:
					state = State.IDLE

			# Input cancelled during poll — return to idle
			elif not has_backward and not has_side:
				state = State.IDLE

		# ── DASH ──────────────────────────────────────────────────────────────
		State.DASH:
			forward_decel = 40
			#print("decel increased")
			dash_timer -= delta
			velocity.x  = dash_velocity.x
			velocity.z  = dash_velocity.z

			# Rotate mesh to face dash direction
			#mesh.rotation.y = lerp_angle(
				#mesh.rotation.y,
				#atan2(dash_velocity.x, dash_velocity.z),
				#0.3
			#)

			if dash_timer <= 0.0:
				#velocity.x = 0.0
				#velocity.z = 0.0
				forward_decel = 30
				print("decel decreased")
				state = State.IDLE

	move_and_slide()
	var speed_ratio := _xz_speed() / MAX_SPEED
	camera.fov = lerp(camera.fov, lerp(FOV_DEFAULT, FOV_MAX, speed_ratio), 0.1)

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		spring_arm.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			-PI / 3.0,
			PI / 6.0
		)

	if event.is_action_pressed("exit"):
		get_tree().quit()
