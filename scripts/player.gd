extends CharacterBody3D

@export var speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0
@export var is_networked: bool = true
@export var ball_spawn_pos: Marker3D
@export var animation_player: AnimationPlayer

var net_ready: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func set_network_ready(v: bool) -> void:
	net_ready = v

func _unhandled_input(event: InputEvent) -> void:
	if (is_multiplayer_authority() and net_ready) || not is_networked:
		if event.is_action_pressed("action_1"):
			trigger_animation("animation_1")
		if event.is_action_pressed("action_2"):
			trigger_animation("animation_2")
		if event.is_action_pressed("action_3"):
			throw_ball()

func _physics_process(delta: float) -> void:
	if (is_multiplayer_authority() and net_ready) || not is_networked:
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

		update_transform.rpc(global_transform)

func throw_ball() -> void:
	var pos : Vector3 = ball_spawn_pos.global_position
	if multiplayer.is_server():
		_spawn_ball(pos)
	else:
		rpc_id(1, "request_spawn_ball", pos)

@rpc("authority", "reliable")
func request_spawn_ball(pos: Vector3) -> void:
	if multiplayer.is_server():
		_spawn_ball(pos)

func _spawn_ball(pos: Vector3) -> void:
	var network_manager = get_tree().get_root().get_node("NetworkManager")
	var object_id = str(Time.get_ticks_msec())
	network_manager.spawn_networked_object("ball", object_id, 1, pos)

# NEW: Local + networked animation trigger
func trigger_animation(animation: String) -> void:
	play_animation(animation)
	# Notify others
	play_animation_remote.rpc(animation)

func play_animation(animation: String) -> void:
	if animation_player:
		animation_player.play(animation)

@rpc("any_peer", "reliable")
func play_animation_remote(animation: String) -> void:
	if (not is_multiplayer_authority() and net_ready) || not is_networked:
		if animation_player:
			animation_player.play(animation)

@rpc("any_peer", "unreliable")
func update_transform(new_transform: Transform3D) -> void:
	if (not is_multiplayer_authority() and net_ready) || not is_networked:
		global_transform = new_transform
