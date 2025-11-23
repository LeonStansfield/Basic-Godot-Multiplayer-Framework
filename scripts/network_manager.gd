extends Node

signal hosting_started
signal hosting_failed(err_code: int)
signal connecting_started(ip: String)
signal connected
signal connection_failed
signal disconnected

const PORT: int = 8080
const MAX_PLAYERS: int = 16

# Registry for spawnable objects
var spawnable_scenes: Dictionary = {
	"player": preload("res://Prefabs/player.tscn"),
	"ball": preload("res://Prefabs/ball.tscn")
}

var spawn_root: Node3D
var multiplayer_spawner: MultiplayerSpawner

func _ready() -> void:
	spawn_root = Node3D.new()
	spawn_root.name = "SpawnRoot"
	add_child(spawn_root)
	
	# Setup MultiplayerSpawner
	multiplayer_spawner = MultiplayerSpawner.new()
	multiplayer_spawner.spawn_path = spawn_root.get_path()
	add_child(multiplayer_spawner)
	
	# Register spawnable scenes
	for scene_path in spawnable_scenes.values():
		multiplayer_spawner.add_spawnable_scene(scene_path.resource_path)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# SERVER / CLIENT SETUP
func host_game() -> Error:
	reset_game_state()

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		printerr("Failed to host server: ", err)
		emit_signal("hosting_failed", err)
		return err

	multiplayer.multiplayer_peer = peer
	print("Hosting server on port %d" % PORT)
	emit_signal("hosting_started")

	# Spawn the host's player object.
	spawn_player(1)
	return OK

func join_game(ip: String) -> Error:
	var addr := ip.strip_edges()
	if addr == "" or (addr != "localhost" and not ip.is_valid_ip_address()):
		printerr("Join refused: invalid IP/hostname '%s'" % addr)
		return ERR_INVALID_PARAMETER

	reset_game_state()

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(addr, PORT)
	if err != OK:
		printerr("Failed to create client peer: ", err)
		return err

	multiplayer.multiplayer_peer = peer
	print("Connecting to %s:%d..." % [addr, PORT])
	emit_signal("connecting_started", addr)
	return OK


func exit_game() -> void:
	_close_peer()
	reset_game_state()
	emit_signal("disconnected")

# CONNECTION EVENTS
func _on_connected_to_server() -> void:
	print("Connected to server")
	emit_signal("connected")

func _on_connection_failed() -> void:
	print("Connection failed")
	_close_peer()
	reset_game_state()
	emit_signal("connection_failed")

func _on_server_disconnected() -> void:
	print("Disconnected from server")
	_close_peer()
	reset_game_state()
	emit_signal("disconnected")

# PEER EVENTS
func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	if multiplayer.is_server():
		spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	if multiplayer.is_server():
		var player = spawn_root.get_node_or_null(str(id))
		if player:
			player.queue_free()

func spawn_player(id: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var spawn_offset = Vector3(rng.randf_range(-3, 3), 2.0, rng.randf_range(-3, 3))
	var spawn_pos = spawn_root.global_position + spawn_offset
	
	var player = spawnable_scenes["player"].instantiate()
	player.name = str(id)
	player.position = spawn_pos
	player.set_multiplayer_authority(id)
	spawn_root.add_child(player, true)

# SPAWN BALL (called from player)
func spawn_ball(pos: Vector3, rot: Vector3) -> void:
	if not multiplayer.is_server():
		return # Only server spawns
		
	var ball = spawnable_scenes["ball"].instantiate()
	ball.position = pos
	ball.rotation_degrees = rot
	spawn_root.add_child(ball, true)

func reset_game_state() -> void:
	print("Resetting game state...")
	for child in spawn_root.get_children():
		child.queue_free()

func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		var p := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = null
		if p is ENetMultiplayerPeer:
			(p as ENetMultiplayerPeer).close()
