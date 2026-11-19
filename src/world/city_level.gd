class_name CityLevel
extends Node2D

## Baked Godot level scene holding TileMapLayers, wall colliders, props, and navigation/spawn metadata.

@export var pixel_size: Vector2 = Vector2.ZERO
@export var landmark_nodes: Dictionary = {}
@export var npc_nodes: Dictionary = {}
@export var traffic_nodes: Dictionary = {}
@export var taxi_spawns: Array[Vector2] = []
@export var tutorial_triggers: Array[Dictionary] = []
