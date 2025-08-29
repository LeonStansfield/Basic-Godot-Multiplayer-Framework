extends CharacterBody3D

@export var speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var camera_rig: Node3D
@export var camera: Camera3D
@export var ball_spawn_pos: Marker3D
@export var animation_player: AnimationPlayer

@export var is_networked: bool = true
var networked_object_id: String = ""
var net_ready: bool = false

var mouse_sensitivity: float = 0.1
var camera_pitch: float = 0.0 

func network_ready() -> void:
	net_ready = true
	set_current_camera()

func _set_network_ready(v: bool) -> void:
	net_ready = v

func _ready() -> void:
	set_current_camera()

func _unhandled_input(event: InputEvent) -> void:
	if (is_multiplayer_authority() and net_ready) or not is_networked:
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
	if not is_networked or (net_ready and is_multiplayer_authority()):
		if not is_on_floor():
			velocity.y -= gravity * delta

		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction:
			velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

		move_and_slide()

		# Send transform to others
		update_transform.rpc(global_transform)

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
	if (is_multiplayer_authority() and net_ready) or not is_networked:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false  # Remote players don't render their camera

func throw_ball() -> void:
	var pos: Vector3 = ball_spawn_pos.global_position
	var rot: Vector3 = ball_spawn_pos.global_rotation_degrees
	if multiplayer.is_server():
		_spawn_ball(pos, rot)
	else:
		rpc_id(1, "request_spawn_ball", pos, rot)

@rpc("authority", "reliable")
func request_spawn_ball(pos: Vector3, rot: Vector3) -> void:
	if multiplayer.is_server():
		_spawn_ball(pos, rot)

func _spawn_ball(pos: Vector3, rot: Vector3) -> void:
	var network_manager = get_tree().get_root().get_node("NetworkManager")
	var object_id = str(Time.get_ticks_msec())
	network_manager.spawn_networked_object("ball", object_id, 1, pos, rot, Vector3.ONE)

# Local + networked animation triggers
func trigger_animation(animation: String) -> void:
	play_animation(animation)
	play_animation_remote.rpc(animation)

func play_animation(animation: String) -> void:
	if animation_player:
		animation_player.play(animation)

@rpc("any_peer", "reliable")
func play_animation_remote(animation: String) -> void:
	if (not is_multiplayer_authority() and net_ready) or not is_networked:
		if animation_player:
			animation_player.play(animation)

@rpc("any_peer", "unreliable")
func update_transform(new_transform: Transform3D) -> void:
	if (not is_multiplayer_authority() and net_ready) or not is_networked:
		global_transform = new_transform
