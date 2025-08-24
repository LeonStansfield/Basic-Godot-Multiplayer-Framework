extends Node

signal hosting_started
signal hosting_failed(err_code: int)
signal connecting_started(ip: String)
signal connected
signal connection_failed
signal disconnected

@export var player_scene: PackedScene = preload("res://Prefabs/player.tscn")
@export var spawn_root: NodePath   # Assign to a Node3D (e.g., "SpawnRoot") in the editor

const PORT: int = 12345
const MAX_PLAYERS: int = 4

var players: Dictionary = {}  # peer_id -> Node
var _spawn_root_node: Node

func _ready() -> void:
	_spawn_root_node = get_node(spawn_root)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# ======================
# SERVER / CLIENT SETUP
# ======================
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

	# Host spawns themselves immediately
	spawn_player(multiplayer.get_unique_id())
	return OK


func join_game(ip: String) -> Error:
	# Validate IP quickly; allow "localhost"
	var addr := ip.strip_edges()
	if addr == "" or (addr != "localhost" and not ip.is_valid_ip_address()):
		printerr("Join refused: invalid IP/hostname '%s'" % addr)
		return ERR_INVALID_PARAMETER

	reset_game_state()  # ensure clean state

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(addr, PORT)
	if err != OK:
		printerr("Failed to create client peer: ", err)
		return err

	# Non-blocking: Godot handles the handshake internally.
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s:%d..." % [addr, PORT])
	emit_signal("connecting_started", addr)
	return OK


func exit_game() -> void:
	# Called by UI to leave game or cancel a pending connection.
	_close_peer()
	reset_game_state()
	emit_signal("disconnected")

# ======================
# CONNECTION EVENTS
# ======================
func _on_connected_to_server() -> void:
	print("Connected to server")
	# Client does NOT spawn itself. The server will instruct all clients what to spawn.
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

# ======================
# PEER EVENTS (server-side spawning)
# ======================
func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)

	if multiplayer.is_server():
		# Spawn the new player's character on the server.
		spawn_player(id)

		# 1) Tell the new peer about ALL existing players (including host and itself)
		for existing_id in players.keys():
			rpc_id(id, "spawn_remote_player", existing_id)

		# 2) Tell all existing peers about the new player
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "spawn_remote_player", id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)

	# Server cleans up and tells everyone to despawn
	if multiplayer.is_server():
		despawn_player(id)
		rpc("despawn_remote_player", id)

# ======================
# PLAYER SPAWNING
# ======================
func spawn_player(peer_id: int) -> void:
	if players.has(peer_id):
		despawn_player(peer_id)

	var p := player_scene.instantiate()
	p.name = "Player_%d" % peer_id
	_spawn_root_node.add_child(p)
	p.set_multiplayer_authority(peer_id)

	# Simple random spawn area
	p.global_position = Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))

	if p.has_method("set_network_ready"):
		p.call("set_network_ready", true)

	players[peer_id] = p
	print("Spawned player for peer %d" % peer_id)


@rpc("any_peer", "reliable")
func spawn_remote_player(peer_id: int) -> void:
	spawn_player(peer_id)


@rpc("any_peer", "reliable")
func despawn_remote_player(peer_id: int) -> void:
	despawn_player(peer_id)


func despawn_player(peer_id: int) -> void:
	if players.has(peer_id):
		var node: Node = players[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		players.erase(peer_id)

# ======================
# RESET/CLEANUP
# ======================
func reset_game_state() -> void:
	for id in players.keys():
		var n: Node = players[id]
		if is_instance_valid(n):
			n.queue_free()
	players.clear()
	# DO NOT null the multiplayer peer here; _close_peer() handles it.
	print("Game state reset to initial state")


func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		var p := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = null
		if p is ENetMultiplayerPeer:
			(p as ENetMultiplayerPeer).close()
