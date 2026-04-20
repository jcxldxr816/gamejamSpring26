# TagDesign.gd
# Represents a completed tag: the ordered list of TagLayer resources the player
# chose during the creation flow. One TagDesign is created per tagging session
# and then stored on the TagSpot that was tagged.
class_name TagDesign
extends Resource

## Ordered list of chosen layers, one per step of the creation flow.
var chosen_layers: Array[TagLayer] = []

## World position where this tag was placed (set by TagSpot).
var world_position: Vector3 = Vector3.ZERO

## The TagSpot node path this design is attached to (set by TagSpot).
var spot_path: NodePath

## Timestamp (unix time) when the tag was placed.
var placed_at: float = 0.0

func _init() -> void:
	placed_at = Time.get_unix_time_from_system()

## Returns a string key that uniquely identifies this combination of layers,
## useful for the record system later.
func get_signature() -> String:
	var parts: Array[String] = []
	for layer in chosen_layers:
		parts.append(layer.label)
	return "+".join(parts)
