##
# GameServer.gd
#
# The GameServer is responsible for orchestrating multiplayer sessions.  When
# running as a server it listens for incoming client connections using
# Godot's high level networking API (ENetMultiplayerPeer) and assigns
# connecting peers to GameSession instances.  Each GameSession represents
# a complete game for a group of up to `MAX_PLAYERS` students.  Once a
# session reaches capacity a new GameSession is created and subsequent
# players are assigned to it.
#
# When running as a client the GameServer attempts to connect to a
# specified host and port.  Upon successful connection the server
# designates the client to a session and spawns the appropriate
# GameSession on the client via remote procedure calls.
#
# This script is intentionally verbose and heavily commented to aid
# understanding and maintenance.  Networking can be challenging and
# having clear documentation here will benefit future developers.
#
extends Node

## The maximum number of players permitted in a single game session.
## This value can be tuned by editing the constant below.  Once a
## session has this many players a new session will be created.
const MAX_PLAYERS : int = 10

## Port to host the server on.  Clients must connect to this port.
const SERVER_PORT : int = 25000

## IP address of the server to connect to when running as a client.
## In a real deployment this might come from a configuration file or
## command line argument.  For now it defaults to localhost for
## ease of testing.
const DEFAULT_SERVER_ADDRESS : String = "127.0.0.1"

## Container for active sessions.  Each element is a dictionary with
## keys:
##   id:        The session's unique identifier
##   players:   Array of peer IDs currently assigned to the session
##   node:      The actual GameSession node instance managing the game
var sessions : Array = []

## Internal counter used to assign unique session identifiers.  This
## increments each time a new session is created.  Session IDs are
## used so that clients know which session they belong to on the
## server.
var _next_session_id : int = 1

## The underlying multiplayer peer used by Godot to send and receive
## network packets.  Both server and client roles assign this.
var _multiplayer_peer : ENetMultiplayerPeer = null

## Called when the node enters the scene tree.  Determines whether
## this instance will run as a server or as a client.  In the editor
## and by default the script will start as a server to allow local
## testing without command line arguments.  When running from the
## command line a `--client` flag can be provided to force client
## behaviour.
func _ready() -> void:
	# Decide whether to host or connect.  Godot exposes command line
	# arguments via OS.get_cmdline_args().  If the user passes
	# `--client` then we attempt to connect to a running server.
	var args : Array = OS.get_cmdline_args()
	var as_client : bool = args.has("--client")
	if as_client:
		var address := DEFAULT_SERVER_ADDRESS
		var port := SERVER_PORT
		# The user may provide --address=<ip> or --port=<number>
		for a in args:
			if a.begins_with("--address="):
				address = a.get_slice("=", 1)
			if a.begins_with("--port="):
				port = int(a.get_slice("=", 1))
		connect_to_server(address, port)
	else:
		start_server(SERVER_PORT)

## Starts the server and begins listening for incoming connections.
## This method should only be called on the host machine.  The
## creation of the first session occurs automatically.
func start_server(port: int) -> void:
	_multiplayer_peer = ENetMultiplayerPeer.new()
	var result := _multiplayer_peer.create_server(port)
	if result != OK:
		push_error("Failed to create ENet server on port %d (error %d)" % [port, result])
		return

	# Attach the ENet peer to this node's MultiplayerAPI.
	multiplayer.multiplayer_peer = _multiplayer_peer

	# Connect signals for peer join and leave events. When a client
	# connects the server assigns the player to a session via
	# `_on_peer_connected`. Disconnection cleans up references.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Create the initial session so the first player has a game to join.
	_create_new_session()
	print("Server started on port %d" % port)


## Connects to an existing server. This method should only be called
## on clients. On successful connection the server will assign the
## client to a session via the `_client_assign_session` RPC.
func connect_to_server(address: String, port: int) -> void:
	_multiplayer_peer = ENetMultiplayerPeer.new()
	var result := _multiplayer_peer.create_client(address, port)
	if result != OK:
		push_error("Failed to connect to server %s:%d (error %d)" % [address, port, result])
		return

	# Attach the ENet peer to this node's MultiplayerAPI.
	multiplayer.multiplayer_peer = _multiplayer_peer

	# Connect signals to detect when we have joined the network.
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	print("Connecting to server %s:%d" % [address, port])

## Creates a new GameSession instance and registers it internally.
## When called on the server, this method instantiates a new
## GameSession scene, adds it as a child of the GameServer and
## assigns a unique session ID.  The new session is returned so the
## caller can populate it with players.
func _create_new_session() -> Dictionary:
	var session_scene : PackedScene = load("res://Scenes/GameSession.tscn")
	var session_node : Node2D = session_scene.instantiate()
	var session_id : int = _next_session_id
	_next_session_id += 1
	session_node.name = "Session_%d" % session_id
	# Assign the session ID on the GameSession script if it defines
	# such a property.  The annotation checks protect against errors
	# if the property is renamed.
	if "session_id" in session_node:
		session_node.set("session_id", session_id)
	add_child(session_node)
	var session : Dictionary = {
		"id": session_id,
		"players": [],
		"node": session_node
	}
	sessions.append(session)
	print("Created new session %d" % session_id)
	return session

## Returns a session with available capacity or null if none exist.
func _get_open_session() -> Dictionary:
	for s in sessions:
		if s["players"].size() < MAX_PLAYERS:
			return s
	return {}

## Called on the server when a new peer connects.  Assign the peer
## to a session.  If no session has space, create a new one.
func _on_peer_connected(id: int) -> void:
	print("Peer %d connected" % id)
	var session : Dictionary = _get_open_session()
	if session.is_empty():
		session = _create_new_session()
	session["players"].append(id)
	# Inform the connecting client which session they are joining.
	# We use RPC to call `_client_assign_session` on the client side.
	# The client will then request the server to spawn their player.
	rpc_id(id, "_client_assign_session", session["id"])
	# Spawn the player character on the server.  This ensures
	# consistent authority across the network.  Note that this must
	# happen after informing the client of their session ID or the
	# client may attempt to control the wrong session.
	session["node"].call_deferred("spawn_player", id)

## Called on the server when a peer disconnects.  Cleans up the
## player's entry from the session and removes their character.
func _on_peer_disconnected(id: int) -> void:
	print("Peer %d disconnected" % id)
	for s in sessions:
		if id in s["players"]:
			s["players"].erase(id)
			# Tell the session to remove the player's character.
			s["node"].call_deferred("remove_player", id)
			break

## Called on the client when the connection to the server succeeds.
## At this point the client waits for the server to assign them to
## a session via `_client_assign_session`.
func _on_connected_to_server() -> void:
	print("Connected to server")

## Called on the client when connection to the server fails.
func _on_connection_failed() -> void:
	push_error("Failed to connect to server")

## Remote procedure called by the server on a client to assign the
## client to a particular session.  The client stores the session ID
## for informational purposes and may take appropriate actions such
## as enabling the HUD.  All spawning happens on the server.
@rpc
func _client_assign_session(session_id: int) -> void:
	# Store the assigned session ID.  In a more complex client this
	# could be used to show which lobby the player is in.
	print("Assigned to session %d" % session_id)
