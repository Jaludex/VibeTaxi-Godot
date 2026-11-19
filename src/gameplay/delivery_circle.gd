class_name DeliveryCircle
extends Node2D

## Draws the green destination drop-off ring on the ground layer.


func _draw() -> void:
	draw_arc(
		Vector2.ZERO,
		GameConstants.PASSENGER_DELIVERY_RADIUS,
		0.0,
		TAU,
		48,
		GameConstants.COLOR_PASSENGER_DELIVERY,
		2.0
	)
