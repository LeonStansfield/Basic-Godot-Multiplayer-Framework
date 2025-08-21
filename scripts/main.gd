extends Node

@onready var ip_input = $Control/IPAddress
@onready var host_button = $Control/Host
@onready var join_button = $Control/Join
@onready var start_area = $SpawnPoint

const PORT = 12345
const MAX_PLAYERS = 4
var player_scene = preload("res://Prefabs/player.tscn")

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(join_game)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_connected.connect(_on_peer_connected)

func host_game():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	print("Hosting on port %d" % PORT)
	spawn_player(multiplayer.get_unique_id())

func join_game():
	var ip = ip_input.text.strip_edges()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		print("Failed to connect")
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % ip)

func _on_connected():
	print("Connected to server")

func _on_peer_connected(id):
	if multiplayer.is_server():
		spawn_player.rpc_id(id, id)

@rpc("any_peer")
func spawn_player(peer_id):
	var player = player_scene.instantiate()
	# Randomize spawn position slightly
	player.global_position = start_area.global_position + Vector3(randf()*5, 0, randf()*5)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
