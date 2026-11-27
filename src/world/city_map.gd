class_name CityMap
extends Node2D

## Loads a Tiled JSON map into Godot TileMapLayers, static colliders, props, and node graphs.

const PROP_SCENE: PackedScene = preload("res://src/world/prop.tscn")
const BURST_SCENE: PackedScene = preload("res://src/effects/burst_particles.tscn")
const NIGHT_GLOW_TEXTURE: Texture2D = preload("res://assets/graphics/city_tileset_night_glow.png")
const NIGHT_GLOW_LAYERS: Array[String] = ["decoration-low", "buildings", "decoration-high", "overheads"]
const NIGHT_GLOW_TINT: Color = Color(0.96, 0.90, 0.72, 1.0)
const NIGHT_GLOW_MAX_ALPHA: float = 0.82

@onready var _layers_root: Node2D = $MapLayers
@onready var _walls_body: StaticBody2D = $WallsBody
@onready var _props_root: Node2D = $PropsRoot
@onready var _ground_effects: Node2D = $GroundEffects
@onready var _entities_root: Node2D = $EntitiesRoot
@onready var _air_effects: Node2D = $AirEffects
@onready var _silhouettes_root: Node2D = $SilhouettesRoot
@onready var _debug_overlay: DebugOverlay = $DebugOverlay

var map_key: String = "city"
var muted: bool = false
var pixel_size: Vector2 = Vector2.ZERO
var tile_layers: Dictionary = {}
var collision_rects: Array[Rect2] = []
var landmark_nodes: Dictionary = {}
var npc_nodes: Dictionary = {}
var traffic_nodes: Dictionary = {}
var taxi_spawns: Array[Vector2] = []
var tutorial_triggers: Array[Dictionary] = []

var _overheads_layer: TileMapLayer = null
var _night_glow_layers: Array[TileMapLayer] = []
var _night_intensity: float = 0.0


func _ready() -> void:
	if _debug_overlay != null:
		_debug_overlay.city_map = self


func load_map(p_map_key: String = "city", spawn_props: bool = true) -> void:
	map_key = p_map_key
	_clear_existing()

	var baked_path: String = "res://src/world/maps/%s_level.tscn" % map_key
	if ResourceLoader.exists(baked_path):
		var packed: PackedScene = load(baked_path) as PackedScene
		var level: CityLevel = packed.instantiate() as CityLevel if packed != null else null
		if level != null:
			_load_from_baked_level(level, spawn_props)
			level.free()
			_build_night_glow_layers()
			if _debug_overlay != null:
				_debug_overlay.queue_redraw()
			return

	var parsed: Dictionary = TiledMapLoader.parse_map(map_key)
	if parsed.is_empty():
		return

	pixel_size = parsed["pixel_size"] as Vector2
	tile_layers = TiledMapLoader.build_tilemap_layers(parsed, _layers_root)
	_overheads_layer = tile_layers.get("overheads", null) as TileMapLayer
	_build_night_glow_layers()

	collision_rects = parsed["collisions"] as Array[Rect2]
	landmark_nodes = parsed["landmark_nodes"] as Dictionary
	npc_nodes = parsed["npc_nodes"] as Dictionary
	traffic_nodes = parsed["traffic_nodes"] as Dictionary
	taxi_spawns = parsed["taxi_spawns"] as Array[Vector2]
	tutorial_triggers = parsed["tutorial_triggers"] as Array[Dictionary]

	_build_wall_colliders()
	if spawn_props:
		_build_props(parsed["props"] as Array[Dictionary])

	if _debug_overlay != null:
		_debug_overlay.queue_redraw()


func _load_from_baked_level(level: CityLevel, spawn_props: bool) -> void:
	pixel_size = level.pixel_size
	landmark_nodes = level.landmark_nodes
	npc_nodes = level.npc_nodes
	traffic_nodes = level.traffic_nodes
	taxi_spawns = level.taxi_spawns
	tutorial_triggers = level.tutorial_triggers

	var baked_layers: Node2D = level.get_node_or_null("MapLayers") as Node2D
	if baked_layers != null:
		for child in baked_layers.get_children():
			baked_layers.remove_child(child)
			child.owner = null
			_layers_root.add_child(child)
			if child is TileMapLayer:
				tile_layers[child.name] = child
	_overheads_layer = tile_layers.get("overheads", null) as TileMapLayer

	_walls_body.collision_layer = GameConstants.LAYER_WALLS
	_walls_body.collision_mask = 0
	collision_rects.clear()
	var baked_walls: StaticBody2D = level.get_node_or_null("WallsBody") as StaticBody2D
	if baked_walls != null:
		for child in baked_walls.get_children():
			baked_walls.remove_child(child)
			child.owner = null
			_walls_body.add_child(child)
			if child is CollisionShape2D:
				var cs: CollisionShape2D = child as CollisionShape2D
				if cs.shape is RectangleShape2D:
					var sz: Vector2 = (cs.shape as RectangleShape2D).size
					collision_rects.append(Rect2(cs.position - sz * 0.5, sz))

	if spawn_props:
		var baked_props: Node2D = level.get_node_or_null("PropsRoot") as Node2D
		if baked_props != null:
			for child in baked_props.get_children():
				baked_props.remove_child(child)
				child.owner = null
				_props_root.add_child(child)


func _clear_existing() -> void:
	for child in _layers_root.get_children():
		child.queue_free()
	for child in _walls_body.get_children():
		child.queue_free()
	for child in _props_root.get_children():
		child.queue_free()
	for child in _silhouettes_root.get_children():
		child.queue_free()
	if _ground_effects.has_method("clear_marks"):
		_ground_effects.call("clear_marks")
	tile_layers.clear()
	_night_glow_layers.clear()
	_night_intensity = 0.0
	_overheads_layer = null


func _build_night_glow_layers() -> void:
	_night_glow_layers.clear()
	var glow_tileset: TileSet = null
	var glow_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	glow_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

	for lname in NIGHT_GLOW_LAYERS:
		var src: TileMapLayer = tile_layers.get(lname, null) as TileMapLayer
		if src == null or src.tile_set == null:
			continue
		if glow_tileset == null:
			glow_tileset = _create_night_glow_tileset(src.tile_set)
			if glow_tileset == null:
				return
		var glow_layer: TileMapLayer = TileMapLayer.new()
		glow_layer.name = lname + "_night_glow"
		glow_layer.tile_set = glow_tileset
		glow_layer.tile_map_data = src.tile_map_data
		glow_layer.z_index = src.z_index
		glow_layer.collision_enabled = false
		glow_layer.navigation_enabled = false
		glow_layer.material = glow_mat
		glow_layer.visible = false
		glow_layer.modulate = Color(NIGHT_GLOW_TINT.r, NIGHT_GLOW_TINT.g, NIGHT_GLOW_TINT.b, 0.0)
		_layers_root.add_child(glow_layer)
		_layers_root.move_child(glow_layer, src.get_index() + 1)
		_night_glow_layers.append(glow_layer)


func _create_night_glow_tileset(base_ts: TileSet) -> TileSet:
	var glow_ts: TileSet = TileSet.new()
	glow_ts.tile_size = base_ts.tile_size
	var added_city: bool = false
	for i in base_ts.get_source_count():
		var sid: int = base_ts.get_source_id(i)
		var atlas: TileSetAtlasSource = base_ts.get_source(sid) as TileSetAtlasSource
		if atlas == null or atlas.texture == null:
			continue
		if not atlas.texture.resource_path.ends_with("city_tileset.png"):
			continue
		var cloned: TileSetAtlasSource = atlas.duplicate() as TileSetAtlasSource
		cloned.texture = NIGHT_GLOW_TEXTURE
		glow_ts.add_source(cloned, sid)
		added_city = true
	return glow_ts if added_city else null


func set_night_intensity(intensity: float) -> void:
	var clamped: float = clampf(intensity, 0.0, 1.0)
	if absf(clamped - _night_intensity) < 0.008:
		return
	_night_intensity = clamped
	# Fade building lights in smoothly once dusk starts, staying off in daylight.
	var alpha: float = clampf((_night_intensity - 0.12) / 0.72, 0.0, 1.0) * NIGHT_GLOW_MAX_ALPHA
	var show_glow: bool = alpha > 0.01
	var col: Color = Color(NIGHT_GLOW_TINT.r, NIGHT_GLOW_TINT.g, NIGHT_GLOW_TINT.b, alpha)
	for layer in _night_glow_layers:
		if is_instance_valid(layer):
			layer.visible = show_glow
			if show_glow:
				layer.modulate = col


func _build_wall_colliders() -> void:
	_walls_body.collision_layer = GameConstants.LAYER_WALLS
	_walls_body.collision_mask = 0
	for rect in collision_rects:
		var cs: CollisionShape2D = CollisionShape2D.new()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = rect.size
		cs.shape = shape
		cs.position = rect.position + rect.size * 0.5
		_walls_body.add_child(cs)


func _build_props(props_data: Array[Dictionary]) -> void:
	for p in props_data:
		var tile_idx: int = int(p["tile_index"])
		if not GameConstants.PROP_DEFS.has(tile_idx):
			continue
		var prop: PropEntity = PROP_SCENE.instantiate() as PropEntity
		prop.setup(p["pos"] as Vector2, tile_idx)
		_props_root.add_child(prop)


func get_map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, pixel_size)


func get_random_taxi_spawn(fallback: Vector2 = Vector2(400.0, 300.0)) -> Vector2:
	if taxi_spawns.is_empty():
		return fallback
	return taxi_spawns[randi() % taxi_spawns.size()]


func get_all_node_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for pos in landmark_nodes.values():
		positions.append(pos as Vector2)
	for info in npc_nodes.values():
		positions.append((info as Dictionary)["pos"] as Vector2)
	return positions


func is_point_under_overhead(world_pos: Vector2) -> bool:
	if _overheads_layer == null:
		return false
	var local_pos: Vector2 = _overheads_layer.to_local(world_pos)
	var cell: Vector2i = _overheads_layer.local_to_map(local_pos)
	return _overheads_layer.get_cell_source_id(cell) != -1


func line_intersects_building(p1: Vector2, p2: Vector2) -> bool:
	var seg_rect: Rect2 = Rect2(p1, Vector2.ZERO).expand(p2)
	for r in collision_rects:
		if not r.intersects(seg_rect):
			continue
		var deflated: Rect2 = r.grow(-3.0)
		if deflated.size.x <= 0.0 or deflated.size.y <= 0.0:
			continue
		if _segment_intersects_rect(p1, p2, deflated):
			return true
	return false


static func _segment_intersects_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	if rect.has_point(p1) or rect.has_point(p2):
		return true
	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	return (
		Geometry2D.segment_intersects_segment(p1, p2, tl, tr) != null
		or Geometry2D.segment_intersects_segment(p1, p2, tr, br) != null
		or Geometry2D.segment_intersects_segment(p1, p2, br, bl) != null
		or Geometry2D.segment_intersects_segment(p1, p2, bl, tl) != null
	)


func resolve_point_outside_buildings(pos: Vector2, half_extent: float = 7.5) -> Vector2:
	var result: Vector2 = pos
	for r in collision_rects:
		var box: Rect2 = Rect2(result.x - half_extent, result.y - half_extent, half_extent * 2.0, half_extent * 2.0)
		if r.intersects(box):
			var overlap_left: float = box.end.x - r.position.x
			var overlap_right: float = r.end.x - box.position.x
			var overlap_top: float = box.end.y - r.position.y
			var overlap_bottom: float = r.end.y - box.position.y
			var min_ov: float = minf(minf(overlap_left, overlap_right), minf(overlap_top, overlap_bottom))
			if min_ov == overlap_left:
				result.x = r.position.x - half_extent
			elif min_ov == overlap_right:
				result.x = r.end.x + half_extent
			elif min_ov == overlap_top:
				result.y = r.position.y - half_extent
			else:
				result.y = r.end.y + half_extent
	return result


func get_entities_root() -> Node2D:
	return _entities_root


func get_ground_effects() -> Node2D:
	return _ground_effects


func get_air_effects() -> Node2D:
	return _air_effects


func get_silhouettes_root() -> Node2D:
	return _silhouettes_root


func spawn_sparks(world_pos: Vector2, count: int = 12) -> void:
	var particles: CPUParticles2D = BURST_SCENE.instantiate() as CPUParticles2D
	particles.position = world_pos
	particles.lifetime = 0.25
	particles.initial_velocity_min = 20.0
	particles.initial_velocity_max = 65.0
	particles.scale_amount_max = 3.0
	_air_effects.add_child(particles)
	particles.call("trigger", Color(1.0, 0.88, 0.25), count, 0.0)
