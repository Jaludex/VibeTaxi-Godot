class_name TiledMapLoader
extends RefCounted

## Parses Tiled JSON maps (.json) and builds Godot TileMapLayers, colliders, and metadata.

const LAYER_Z_INDEX: Dictionary = {
	"ground": 0,
	"decoration-low": 2,
	"buildings": 3,
	"decoration-high": 8,
	"overheads": 9,
}

static var _tileset_cache: Dictionary = {}


static func load_json(map_key: String) -> Dictionary:
	var path: String = "res://assets/tilemaps/%s.json" % map_key
	if not FileAccess.file_exists(path):
		push_error("TiledMapLoader: missing map file %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func parse_map(map_key: String) -> Dictionary:
	var data: Dictionary = load_json(map_key)
	if data.is_empty():
		return {}

	var tile_w: int = int(data.get("tilewidth", GameConstants.TILE_SIZE))
	var tile_h: int = int(data.get("tileheight", GameConstants.TILE_SIZE))
	var cols: int = int(data.get("width", 0))
	var rows: int = int(data.get("height", 0))

	var tilesets_meta: Array[Dictionary] = []
	for ts in (data.get("tilesets", []) as Array):
		var ts_dict: Dictionary = ts as Dictionary
		tilesets_meta.append({
			"firstgid": int(ts_dict.get("firstgid", 1)),
			"columns": int(ts_dict.get("columns", 1)),
			"tilecount": int(ts_dict.get("tilecount", 0)),
			"tilewidth": int(ts_dict.get("tilewidth", tile_w)),
			"tileheight": int(ts_dict.get("tileheight", tile_h)),
			"image": _resolve_image_path(str(ts_dict.get("image", ""))),
		})
	tilesets_meta.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["firstgid"]) < int(b["firstgid"])
	)

	var tile_layers: Array[Dictionary] = []
	var collisions: Array[Rect2] = []
	var props: Array[Dictionary] = []
	var landmark_nodes: Dictionary = {}
	var npc_nodes: Dictionary = {}
	var traffic_nodes: Dictionary = {}
	var taxi_spawns: Array[Vector2] = []
	var tutorial_triggers: Array[Dictionary] = []

	_collect_layers(
		data.get("layers", []) as Array,
		tile_layers,
		collisions,
		props,
		landmark_nodes,
		npc_nodes,
		traffic_nodes,
		taxi_spawns,
		tutorial_triggers
	)

	return {
		"tile_size": Vector2i(tile_w, tile_h),
		"grid_size": Vector2i(cols, rows),
		"pixel_size": Vector2(cols * tile_w, rows * tile_h),
		"tilesets_meta": tilesets_meta,
		"tile_layers": tile_layers,
		"collisions": collisions,
		"props": props,
		"landmark_nodes": landmark_nodes,
		"npc_nodes": npc_nodes,
		"traffic_nodes": traffic_nodes,
		"taxi_spawns": taxi_spawns,
		"tutorial_triggers": tutorial_triggers,
	}


static func build_tilemap_layers(parsed: Dictionary, parent: Node2D) -> Dictionary:
	var tile_set: TileSet = _get_or_create_tileset(parsed)
	var layers_by_name: Dictionary = {}
	var cols: int = (parsed["grid_size"] as Vector2i).x
	var tilesets_meta: Array = parsed["tilesets_meta"] as Array

	for layer_info in (parsed["tile_layers"] as Array):
		var info: Dictionary = layer_info as Dictionary
		var layer_name: String = str(info["name"])
		var tml: TileMapLayer = TileMapLayer.new()
		tml.name = layer_name
		tml.tile_set = tile_set
		tml.z_index = int(LAYER_Z_INDEX.get(layer_name, 0))
		tml.collision_enabled = false
		tml.navigation_enabled = false

		var grid_data: Array = info["data"] as Array
		for i in grid_data.size():
			var raw_gid: int = int(grid_data[i])
			if raw_gid == 0:
				continue
			# Strip Tiled flip/rotate bits if present
			var gid: int = raw_gid & 0x1FFFFFFF
			var source_idx: int = _find_tileset_index(tilesets_meta, gid)
			if source_idx < 0:
				continue
			var ts_meta: Dictionary = tilesets_meta[source_idx] as Dictionary
			var local_id: int = gid - int(ts_meta["firstgid"])
			var ts_cols: int = maxi(1, int(ts_meta["columns"]))
			@warning_ignore("integer_division")
			var atlas_coords: Vector2i = Vector2i(local_id % ts_cols, local_id / ts_cols)
			@warning_ignore("integer_division")
			var cell_coords: Vector2i = Vector2i(i % cols, i / cols)
			tml.set_cell(cell_coords, source_idx, atlas_coords)

		parent.add_child(tml)
		layers_by_name[layer_name] = tml

	return layers_by_name


static func _get_or_create_tileset(parsed: Dictionary) -> TileSet:
	var tilesets_meta: Array = parsed["tilesets_meta"] as Array
	var cache_key: String = str(parsed["tile_size"]) + "|" + str(tilesets_meta)
	if _tileset_cache.has(cache_key):
		return _tileset_cache[cache_key] as TileSet

	var ts: TileSet = TileSet.new()
	ts.tile_size = parsed["tile_size"] as Vector2i

	for meta_var in tilesets_meta:
		var meta: Dictionary = meta_var as Dictionary
		var tex: Texture2D = load(str(meta["image"])) as Texture2D
		if tex == null:
			continue
		var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(int(meta["tilewidth"]), int(meta["tileheight"]))
		var ts_cols: int = maxi(1, int(meta["columns"]))
		var tile_count: int = int(meta["tilecount"])
		for local_id in tile_count:
			@warning_ignore("integer_division")
			var coords: Vector2i = Vector2i(local_id % ts_cols, local_id / ts_cols)
			atlas.create_tile(coords)
		ts.add_source(atlas)

	_tileset_cache[cache_key] = ts
	return ts


static func clear_cache() -> void:
	_tileset_cache.clear()


static func _find_tileset_index(tilesets_meta: Array, gid: int) -> int:
	var best_idx: int = -1
	for i in tilesets_meta.size():
		var firstgid: int = int((tilesets_meta[i] as Dictionary)["firstgid"])
		if gid >= firstgid:
			best_idx = i
		else:
			break
	return best_idx


static func _resolve_image_path(rel_path: String) -> String:
	var filename: String = rel_path.get_file()
	return "res://assets/graphics/%s" % filename


static func _collect_layers(
	layers: Array,
	tile_layers: Array[Dictionary],
	collisions: Array[Rect2],
	props: Array[Dictionary],
	landmark_nodes: Dictionary,
	npc_nodes: Dictionary,
	traffic_nodes: Dictionary,
	taxi_spawns: Array[Vector2],
	tutorial_triggers: Array[Dictionary]
) -> void:
	for raw_layer in layers:
		var layer: Dictionary = raw_layer as Dictionary
		var ltype: String = str(layer.get("type", ""))
		if ltype == "group":
			_collect_layers(
				layer.get("layers", []) as Array,
				tile_layers, collisions, props, landmark_nodes, npc_nodes,
				traffic_nodes, taxi_spawns, tutorial_triggers
			)
		elif ltype == "tilelayer":
			tile_layers.append({
				"name": str(layer.get("name", "")),
				"data": layer.get("data", []),
			})
		elif ltype == "objectgroup":
			var group_name: String = str(layer.get("name", ""))
			var objs: Array = layer.get("objects", []) as Array
			match group_name:
				"collisions":
					_parse_collisions(objs, collisions)
				"props":
					_parse_props(objs, props)
				"nodes":
					_parse_nodes(objs, landmark_nodes, npc_nodes)
				"traffic-nodes":
					_parse_traffic_nodes(objs, traffic_nodes)
				"taxi-spawns":
					_parse_taxi_spawns(objs, taxi_spawns)
				"tutorial_triggers":
					_parse_tutorial_triggers(objs, tutorial_triggers)


static func _props_dict(obj: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Variant = obj.get("properties", [])
	if raw is Dictionary:
		return (raw as Dictionary).duplicate()
	if raw is Array:
		for item in (raw as Array):
			if item is Dictionary and (item as Dictionary).has("name"):
				var d: Dictionary = item as Dictionary
				out[str(d["name"])] = d.get("value")
	return out


static func _parse_collisions(objs: Array, collisions: Array[Rect2]) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		var w: float = float(obj.get("width", 0.0))
		var h: float = float(obj.get("height", 0.0))
		if w <= 0.0 or h <= 0.0:
			continue
		collisions.append(Rect2(float(obj.get("x", 0.0)), float(obj.get("y", 0.0)), w, h))


static func _parse_props(objs: Array, props: Array[Dictionary]) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		var pdict: Dictionary = _props_dict(obj)
		var tile_idx: Variant = pdict.get("tile_index")
		if tile_idx == null:
			continue
		var w: float = float(obj.get("width", 16.0))
		var h: float = float(obj.get("height", 16.0))
		# Tiled tile objects use bottom-left origin (y - h/2 gives center)
		var center: Vector2 = Vector2(float(obj.get("x", 0.0)) + w * 0.5, float(obj.get("y", 0.0)) - h * 0.5)
		props.append({
			"pos": center,
			"size": Vector2(w, h),
			"tile_index": int(tile_idx),
		})


static func _parse_nodes(objs: Array, landmark_nodes: Dictionary, npc_nodes: Dictionary) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		var center: Vector2 = Vector2(
			float(obj.get("x", 0.0)) + float(obj.get("width", 0.0)) * 0.5,
			float(obj.get("y", 0.0)) + float(obj.get("height", 0.0)) * 0.5
		)
		var node_name: String = str(obj.get("name", ""))
		if node_name.is_empty():
			node_name = "node_%d" % (landmark_nodes.size() + npc_nodes.size())

		if node_name.begins_with("npc_"):
			var pdict: Dictionary = _props_dict(obj)
			var next_raw: String = str(pdict.get("next", ""))
			var next_list: Array[String] = []
			for part in next_raw.split(",", false):
				var trimmed: String = part.strip_edges()
				if not trimmed.is_empty():
					next_list.append(trimmed)
			npc_nodes[node_name] = {
				"pos": center,
				"next": next_list,
				"despawn": bool(pdict.get("despawn", false)),
				"dir_despawn": str(pdict.get("dir_despawn", "up")).to_lower(),
			}
		elif not landmark_nodes.has(node_name):
			landmark_nodes[node_name] = center


static func _parse_traffic_nodes(objs: Array, traffic_nodes: Dictionary) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		var center: Vector2 = Vector2(
			float(obj.get("x", 0.0)) + float(obj.get("width", 0.0)) * 0.5,
			float(obj.get("y", 0.0)) + float(obj.get("height", 0.0)) * 0.5
		)
		var pdict: Dictionary = _props_dict(obj)
		var next_raw: String = str(pdict.get("next", ""))
		var next_list: Array[String] = []
		for part in next_raw.split(",", false):
			var trimmed: String = part.strip_edges()
			if not trimmed.is_empty():
				next_list.append(trimmed)
		var node_name: String = str(obj.get("name", ""))
		if node_name.is_empty():
			node_name = "traffic_node_%d" % traffic_nodes.size()
		traffic_nodes[node_name] = {
			"pos": center,
			"next": next_list,
		}


static func _parse_taxi_spawns(objs: Array, taxi_spawns: Array[Vector2]) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		taxi_spawns.append(Vector2(
			float(obj.get("x", 0.0)) + float(obj.get("width", 0.0)) * 0.5,
			float(obj.get("y", 0.0)) + float(obj.get("height", 0.0)) * 0.5
		))


static func _parse_tutorial_triggers(objs: Array, triggers: Array[Dictionary]) -> void:
	for raw_obj in objs:
		var obj: Dictionary = raw_obj as Dictionary
		var pdict: Dictionary = _props_dict(obj)
		triggers.append({
			"rect": Rect2(
				float(obj.get("x", 0.0)),
				float(obj.get("y", 0.0)),
				float(obj.get("width", 0.0)),
				float(obj.get("height", 0.0))
			),
			"message": str(pdict.get("message", "No message provided.")),
			"condition": str(pdict.get("condition", "")),
		})
