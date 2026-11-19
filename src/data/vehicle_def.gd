class_name VehicleDef
extends Resource

## Editable vehicle stats and sprite frame definition for cars and taxis.

@export var id: String = "yellow_taxi"
@export var frame_index: int = 0
@export var max_speed: float = 125.0
@export var acceleration: float = 90.0
@export var friction: float = 300.0
@export var turn_speed: float = 4.0
@export var base_health: float = 100.0
@export var reverse_speed_ratio: float = 0.2
