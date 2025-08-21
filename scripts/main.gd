extends Node

@onready var ip_input = $Control/IPAddress
@onready var host_button = $Control/Host
@onready var join_button = $Control/Join
@onready var exit_button = $Control/Exit
@onready var start_area = $SpawnPoint

const PORT := 12345
const MAX_PLAYERS := 4
var player_scene := preload("res://Prefabs/player.tscn")

# Keep track of spawned players (peer_id -> node)
var players: Dictionary = {}

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(join_game)
	exit_button.pressed.connect(exit_game)

	ip_input.text_changed.connect(_on_ip_text_changed)
	update_join_button_state()

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	multiplayer.peer_connected.connect(_on_peer_connected)       # Fires on server
	multiplayer.peer_disconnected.connect(_on_peer_disconnected) # Fires on server

func _on_ip_text_changed(new_text: String) -> void:
	update_join_button_state()

func update_join_button_state():
	join_button.disabled = ip_input.text.strip_edges() == ""

func host_game():
	reset_game_state()
	_show_game_ui(true)

	var peer := ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	print("Hosting on port %d" % PORT)

	# Host spawns itself locally
	spawn_local(multiplayer.get_unique_id())

func join_game():
	if join_button.disabled:
		return

	reset_game_state()
	_show_game_ui(true)

	var ip: String = ip_input.text.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		print("Failed to create client peer")
		_show_game_ui(false)
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % ip)

func exit_game():
	# Reset all multiplayer state; this automatically closes connections
	reset_game_state()
	_show_game_ui(false)

func _on_connected_to_server():
	print("Connected to server")
	# Wait for server to spawn us; don't spawn early

func _on_connection_failed():
	print("Connection failed")
	reset_game_state()
	_show_game_ui(false)

func _on_server_disconnected():
	print("Disconnected from server")
	reset_game_state()
	_show_game_ui(false)

func _show_game_ui(in_game: bool):
	# Hide Host/Join when in game, show Exit button
	host_button.visible = not in_game
	join_button.visible = not in_game
	ip_input.editable = not in_game
	exit_button.visible = in_game

func _on_peer_connected(id: int):
	if !multiplayer.is_server():
		return
	print("Peer connected: %d" % id)
	spawn_local(id)
	spawn_remote.rpc_id(id, id)
	for existing_id in players.keys():
		if existing_id != id:
			spawn_remote.rpc_id(id, existing_id)
	for peer_id in multiplayer.get_peers():
		if peer_id != id:
			spawn_remote.rpc_id(peer_id, id)

func _on_peer_disconnected(id: int):
	if !multiplayer.is_server():
		return
	print("Peer disconnected: %d" % id)
	for peer_id in multiplayer.get_peers():
		despawn_remote.rpc_id(peer_id, id)
	despawn_local(id)

func spawn_local(peer_id: int):
	if players.has(peer_id):
		despawn_local(peer_id)
	var p: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	p.name = "Player_%s" % str(peer_id)
	add_child(p)
	p.set_multiplayer_authority(peer_id)
	if is_instance_valid(start_area):
		p.global_position = start_area.global_position + Vector3(randf() * 5.0, 0.0, randf() * 5.0)
	if p.has_method("set_network_ready"):
		p.call("set_network_ready", true)
	players[peer_id] = p
	print("Spawned local player node for peer %d" % peer_id)

@rpc("authority")
func spawn_remote(peer_id: int):
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

func reset_game_state():
	for id in players.keys():
		var n: Node = players[id]
		if is_instance_valid(n):
			n.queue_free()
	players.clear()
	multiplayer.multiplayer_peer = null
	print("Game state reset to initial state")
	update_join_button_state()
