extends CharacterBody3D

@export var speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var camera_rig: Node3D
@export var camera: Camera3D
@export var ball_spawn_pos: Marker3D
@export var animation_player: AnimationPlayer

var mouse_sensitivity: float = 0.1
var camera_pitch: float = 0.0 

func _ready() -> void:
	# Disable physics initially to prevent "ejection" from spawn
	set_physics_process(false)
	
	# Defer setup to ensure MultiplayerSpawner has set the position and name
	call_deferred("_setup_networking")

func _setup_networking() -> void:
	# Ensure authority is set correctly based on the final name
	set_multiplayer_authority(str(name).to_int())

	# Important: The synchronizer must have the same authority as the player!
	var synchronizer = $PlayerSynchronizer
	synchronizer.set_multiplayer_authority(get_multiplayer_authority())
	
	set_current_camera()
	
	# Reset velocity to prevent any accumulated momentum
	velocity = Vector3.ZERO
	
	# Disable collision initially to prevent spawn conflicts
	get_node("CollisionShape3D").disabled = true
	
	# Wait for sync
	await get_tree().create_timer(0.1).timeout
	
	if not is_inside_tree():
		return
		
	# Enable collision and physics
	get_node("CollisionShape3D").disabled = false
	set_physics_process(true)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event.is_action_pressed("escape"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if event is InputEventMouseMotion:
		_handle_mouse_look(event)
	
	if event.is_action_pressed("action_1"):
		trigger_animation("animation_1")
	if event.is_action_pressed("action_2"):
		trigger_animation("animation_2")
	if event.is_action_pressed("action_3"):
		throw_ball()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = lerp(velocity.x, direction.x * speed, clamp(acceleration * delta, 0.0, 1.0))
		velocity.z = lerp(velocity.z, direction.z * speed, clamp(acceleration * delta, 0.0, 1.0))
	else:
		velocity.x = lerp(velocity.x, 0.0, clamp(deceleration * delta, 0.0, 1.0))
		velocity.z = lerp(velocity.z, 0.0, clamp(deceleration * delta, 0.0, 1.0))

	move_and_slide()

# Handle looking around
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	var yaw_change = -event.relative.x * mouse_sensitivity
	var pitch_change = -event.relative.y * mouse_sensitivity

	# Rotate player horizontally (yaw)
	rotate_y(deg_to_rad(yaw_change))

	# Adjust pitch and clamp it
	camera_pitch = clamp(camera_pitch + pitch_change, -80, 80)
	camera_rig.rotation_degrees.x = camera_pitch

# Enable/disable camera based on authority
func set_current_camera() -> void:
	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false  # Remote players don't render their camera

func throw_ball() -> void:
	var pos: Vector3 = ball_spawn_pos.global_position
	var rot: Vector3 = ball_spawn_pos.global_rotation_degrees
	if multiplayer.is_server():
		get_tree().get_root().get_node("NetworkManager").spawn_ball(pos, rot)
	else:
		rpc_id(1, "request_spawn_ball", pos, rot)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_ball(pos: Vector3, rot: Vector3) -> void:
	if multiplayer.is_server():
		get_tree().get_root().get_node("NetworkManager").spawn_ball(pos, rot)

# Local + networked animation triggers
func trigger_animation(animation: String) -> void:
	play_animation(animation)
	play_animation_remote.rpc(animation)

func play_animation(animation: String) -> void:
	if animation_player:
		animation_player.play(animation)

@rpc("any_peer", "call_remote", "reliable")
func play_animation_remote(animation: String) -> void:
	if animation_player:
		animation_player.play(animation)
