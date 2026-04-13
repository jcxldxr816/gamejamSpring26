extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY : float = 0.005

@export var spring_arm: SpringArm3D
@export var mesh: MeshInstance3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	
	var cam_yaw = spring_arm.global_transform.basis.get_euler().y
	var flat_basis = Basis(Vector3.UP, cam_yaw)
	var direction = (flat_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		if input_dir.y < 0:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(direction.x, direction.z), 0.15)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Horizontal look
		spring_arm.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		
		# Vertical look
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -PI/3, PI/6)

	if event.is_action_pressed('exit'):
		get_tree().quit()
