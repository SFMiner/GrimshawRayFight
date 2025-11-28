##
# PowerUp.gd
#
# Represents a scale reset power up.  When activated, it restores
# every character within its Area2D to a scale factor of 1.0.  The
# power up is removed immediately after activation.  Only the
# server should process body entry events; clients simply see the
# power up disappear and characters return to normal size when the
# server performs the reset.

extends Node2D

## The radius of the area of effect.  This will automatically set
## the collision shape and the visual size when the scene is
## initialised.
@export var radius : float = 200.0

func _ready() -> void:
    # Set up the collision shape for the Area2D.  This creates a
    # circle with the configured radius.  If this node is instanced
    # on the client the shape will be properly sized but the Area2D
    # will not perform any authoritative actions.
    var shape := CircleShape2D.new()
    shape.radius = radius
    $Area/CollisionShape2D.shape = shape
    # Update visual size to match radius.  The ColorRect draws
    # centred at its top‑left corner, so we offset its position by
    # half its size.  We also set a semi‑transparent colour so
    # players recognise the power up area.
    var size := Vector2(radius * 2.0, radius * 2.0)
    if $Visual:
        $Visual.size = size
        $Visual.position = -size / 2.0
    # Connect body_entered only on the server.  Clients do not
    # perform scale adjustments; they simply observe the state.
    if get_tree().is_multiplayer_server():
        $Area.body_entered.connect(_on_body_entered)

## Called when a body enters the power up's area.  Restores the
## scale of that body to 1.0.  After affecting any body the power
## up is destroyed to prevent multiple triggers.  Note that this
## method only executes on the server.
func _on_body_entered(body: Node) -> void:
    # Only act if the body has the appropriate method to set its
    # scale.  Alaska and Player both define set_scale_factor.
    if body.has_method("set_scale_factor"):
        body.rpc("set_scale_factor", 1.0)
    # Remove the power up from the scene after activation.  Because
    # Area2D emits body_entered for each overlapping body, without
    # queue_free() the power up would attempt to reset characters
    # multiple times.
    queue_free()