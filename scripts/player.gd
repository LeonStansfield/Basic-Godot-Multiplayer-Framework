extends CharacterBody3D

@export var speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0
@export var is_networked: bool = true # Used for testing in singleplayer test scenes

var net_ready: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func set_network_ready(v: bool) -> void:
	net_ready = v

func _physics_process(delta: float) -> void:
	if (is_multiplayer_authority() and net_ready) || not is_networked:
		# Apply gravity when not on the floor
		if not is_on_floor():
			velocity.y -= gravity * delta

		# Get input and create a direction vector relative to player rotation
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		# Handle horizontal movement with acceleration and deceleration
		if direction:
			velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

		move_and_slide()

		update_position.rpc(global_transform)

@rpc("any_peer", "unreliable")
func update_position(new_transform: Transform3D) -> void:
	if (not is_multiplayer_authority() and net_ready) || not is_networked:
		global_transform = new_transform
