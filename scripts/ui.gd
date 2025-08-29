extends Control

@onready var ip_input: LineEdit = $VBoxContainer/IPAddress
@onready var host_button: Button = $VBoxContainer/Host
@onready var join_button: Button = $VBoxContainer/Join
@onready var exit_button: Button = $VBoxContainer/Exit

var _is_connecting := false
var _in_game := false

func _ready() -> void:

	# Buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	ip_input.text_changed.connect(_on_ip_text_changed)

	# NetworkManager signals
	NetworkManager.connect("hosting_started", Callable(self, "_on_hosting_started"))
	NetworkManager.connect("hosting_failed", Callable(self, "_on_hosting_failed"))
	NetworkManager.connect("connecting_started", Callable(self, "_on_connecting_started"))
	NetworkManager.connect("connected", Callable(self, "_on_connected"))
	NetworkManager.connect("connection_failed", Callable(self, "_on_connection_failed"))
	NetworkManager.connect("disconnected", Callable(self, "_on_disconnected"))

	_update_ui()

# BUTTON HANDLERS
func _on_host_pressed() -> void:
	var err: Error = NetworkManager.host_game()
	if err != OK:
		# Stay in menu
		return

func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	# Try to start connecting. If invalid IP or immediate error, do nothing visible.
	var err: Error = NetworkManager.join_game(ip)
	if err != OK:
		_is_connecting = false
		_in_game = false
		_update_ui()
		return

func _on_exit_pressed() -> void:
	NetworkManager.exit_game()
	_is_connecting = false
	_in_game = false
	_update_ui()

func _on_ip_text_changed(_new_text: String) -> void:
	_update_ui()

# NETWORK SIGNAL HANDLERS
func _on_hosting_started() -> void:
	_in_game = true
	_is_connecting = false
	_update_ui()

func _on_hosting_failed(_err_code: int) -> void:
	_in_game = false
	_is_connecting = false
	_update_ui()

func _on_connecting_started(_ip: String) -> void:
	# Show "connecting" state: keep menu visible but lock inputs; EXIT stays enabled.
	_is_connecting = true
	_in_game = false
	_update_ui()

func _on_connected() -> void:
	# Only after real connection do we switch into in-game UI.
	_in_game = true
	_is_connecting = false
	_update_ui()

func _on_connection_failed() -> void:
	_is_connecting = false
	_in_game = false
	_update_ui()

func _on_disconnected() -> void:
	_is_connecting = false
	_in_game = false
	_update_ui()

# UI STATE
func _update_ui() -> void:
	# Exit is always available and enabled
	exit_button.visible = true
	exit_button.disabled = false

	if _in_game:
		# In-game: hide menu controls, keep EXIT visible/enabled
		host_button.visible = false
		join_button.visible = false
		ip_input.editable = false
		host_button.disabled = true
		join_button.disabled = true
		exit_button.disabled = false
	else:
		# Menu visible
		host_button.visible = true
		join_button.visible = true

		# While connecting
		if _is_connecting:
			host_button.disabled = true
			join_button.disabled = true
			ip_input.editable = false
			exit_button.disabled = false
		else:
			host_button.disabled = false
			join_button.disabled = ip_input.text.strip_edges() == ""
			ip_input.editable = true
			exit_button.disabled = true
