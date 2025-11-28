##
# Grimshaw.gd
#
# This script controls Dr. Grimshaw, the antagonist.  Grimshaw is
# responsible for firing the Transmogrifier ray at students and
# Alaska.  He is controlled solely by the server; clients simply
# receive replicated state.  When Grimshaw fires he picks a random
# target and a random scale factor from a predefined list.  If the
# target is a player he calls `multiply_scale(multiplier)` via RPC on
# that player.  If the target is Alaska he does the same.  This
# behaviour imitates the chaotic nature described in the game design.

extends CharacterBody2D

## Time in seconds between Grimshaw's attacks.  Adjust this to
## increase or decrease the difficulty.
@export var fire_interval : float = 3.0

## List of scale factors Grimshaw will choose from when firing his
## ray.  These should reflect the variety described in the game
## design document: values less than 1 shrink players, greater than
## 1 enlarge them.
@export var scale_factors : Array[float] = [0.33, 0.4, 0.5, 2.0, 3.0, 4.0]

## Timer to schedule attacks.  Only runs on the server.
var _attack_timer : Timer

## Cache of GameSession so Grimshaw can access players and Alaska
var _session : Node = null

func _ready() -> void:
    # Determine the parent session.  This assumes Grimshaw is
    # instanced within GameSession.tscn.
    _session = get_parent()
    # Set up attack timer only on server
    if get_tree().is_multiplayer_server():
        _attack_timer = Timer.new()
        _attack_timer.wait_time = fire_interval
        _attack_timer.one_shot = false
        _attack_timer.autostart = true
        _attack_timer.timeout.connect(_on_attack_timer_timeout)
        add_child(_attack_timer)

    # Ensure Grimshaw has a collision shape.  This aids in power up
    # detection should he enter a power up zone inadvertently.  The
    # shape itself is arbitrary since Grimshaw is not controlled by
    # players; its size will be synchronised with his visual by
    # scripts if necessary.
    if has_node("CollisionShape2D"):
        var cs := $CollisionShape2D
        if cs.shape == null:
            cs.shape = RectangleShape2D.new()

## Called periodically on the server to fire at a random target.
func _on_attack_timer_timeout() -> void:
    # Choose a target.  Grimshaw prioritises Alaska if she is in
    # existence and then picks a random player.
    var targets : Array[Node] = []
    if _session and _session.has_node("Alaska"):
        var alaska_node : Node = _session.get_node("Alaska")
        targets.append(alaska_node)
    # Append all players to potential targets
    var players := get_tree().get_nodes_in_group("players")
    for p in players:
        targets.append(p)
    if targets.is_empty():
        return
    # Pick random target
    var target : Node = targets[randi() % targets.size()]
    # Pick random scale factor
    var factor : float = scale_factors[randi() % scale_factors.size()]
    # Fire the ray: call multiply_scale() on the target via RPC.
    if target.has_method("multiply_scale"):
        target.rpc("multiply_scale", factor)
        # Optionally print debug information on the server
        print("Grimshaw hit %s with scale factor %.2f" % [target.name, factor])