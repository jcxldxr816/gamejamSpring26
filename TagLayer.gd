# TagLayer.gd
# A single visual element option within one step of the tag creation process.
# Each layer step offers four of these for the player to choose from.
# Attach a Texture2D (e.g. a simple SVG or PNG shape) to preview_texture
# and a matching decal texture to decal_texture.
class_name TagLayer
extends Resource

## Human-readable name shown in the picker UI.
@export var label: String = "Element"

## Icon shown in the four-option picker during tag creation.
@export var preview_texture: Texture2D

## The actual texture composited onto the final tag decal.
## Should be a transparent-background image the same size as your tag canvas.
@export var decal_texture: Texture2D

## Tint applied to this layer when composited. White = no tint.
@export var tint: Color = Color.WHITE

## Loose category tag for procedural weighting (e.g. "base", "fill", "accent").
@export var category: String = "base"
