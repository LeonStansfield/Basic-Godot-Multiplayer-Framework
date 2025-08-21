extends Node

@onready var ip_input = $Control/IPAddress
@onready var host_button = $Control/Host
@onready var join_button = $Control/Join
@onready var start_area = $SpawnPoint

const PORT = 12345
const MAX_PLAYERS = 4
var player_scene = preload("res://Prefabs/player.tscn")

# Keep track of spawned players (peer_id -> node)
var players: Dictionary = {}

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(join_game)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	multiplayer.peer_connected.connect(_on_peer_connected)       # Fires on server
	multiplayer.peer_disconnected.connect(_on_peer_disconnected) # Fires on server

func host_game():
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	print("Hosting on port %d" % PORT)

	# Host spawns itself locally
	spawn_local(multiplayer.get_unique_id())

func join_game():
	var ip: String = ip_input.text.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		print("Failed to create client peer")
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % ip)

func _on_connected_to_server():
	print("Connected to server")
	# Client spawns itself locally
	spawn_local(multiplayer.get_unique_id())

func _on_connection_failed():
	print("Connection failed")

func _on_server_disconnected():
	print("Disconnected from server")

func _on_peer_connected(id: int):
	# SERVER ONLY: a new client arrived.
	if !multiplayer.is_server():
		return

	print("Peer connected: %d" % id)

	# 1) Server spawns the NEW client's player locally
	spawn_local(id)

	# 2) Tell the new client to spawn all EXISTING players (including host and any other clients)
	for existing_id in players.keys():
		# New client will create a matching node with the same deterministic name.
		if existing_id != id:
			spawn_remote.rpc_id(id, existing_id)

	# 3) Tell EVERYONE (including the new client) to spawn the NEW client
	spawn_remote.rpc(id)

func _on_peer_disconnected(id: int):
	# SERVER ONLY: clean up on disconnect, tell everyone to despawn
	if !multiplayer.is_server():
		return
	print("Peer disconnected: %d" % id)
	despawn_remote.rpc(id)       # tell all clients
	despawn_local(id)            # also remove on server

func spawn_local(peer_id: int):
	if players.has(peer_id):
		return # already spawned

	var p := player_scene.instantiate()

	# Deterministic name so both sides share the same NodePath
	p.name = "Player_%s" % str(peer_id)

	# Add to the same parent path on all peers BEFORE setting transforms
	add_child(p)

	# Assign authority BEFORE any RPCs run
	p.set_multiplayer_authority(peer_id)

	# Now safe to position (node is inside tree)
	if is_instance_valid(start_area):
		p.global_position = start_area.global_position + Vector3(randf() * 5.0, 0.0, randf() * 5.0)

	players[peer_id] = p
	print("Spawned local player node for peer %d" % peer_id)

@rpc("authority")
func spawn_remote(peer_id: int):
	# Runs on clients when server tells them to spawn someone
	spawn_local(peer_id)

@rpc("authority")
func despawn_remote(peer_id: int):
	despawn_local(peer_id)

func despawn_local(peer_id: int):
	if players.has(peer_id):
		var n: Node = players[peer_id]
		if is_instance_valid(n):
			n.queue_free()
		players.erase(peer_id)
