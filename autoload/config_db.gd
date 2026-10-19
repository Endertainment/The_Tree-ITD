extends Node
## Loads every data resource into `id -> Resource` dictionaries at startup.
##
## Stage 1 defines the API with untyped `Resource` values; stage 2 replaces the
## generic check with the typed `EnemyData`, `TowerData`, ... subclasses.

const DATA_DIRS := {
	"enemies": "res://data/enemies",
	"towers": "res://data/towers",
	"waves": "res://data/waves",
	"upgrades": "res://data/upgrades",
	"cards": "res://data/cards",
	"missions": "res://data/missions",
	"shop": "res://data/shop",
}

var _by_kind: Dictionary = {}


func _ready() -> void:
	reload_all()


## Re-reads every data directory. Safe on empty folders.
func reload_all() -> void:
	_by_kind.clear()
	for kind: String in DATA_DIRS:
		_by_kind[kind] = _load_directory(DATA_DIRS[kind])


func get_enemy(id: String) -> Resource:
	return _lookup("enemies", id)


func get_tower(id: String) -> Resource:
	return _lookup("towers", id)


func get_wave_table(id := "main") -> Resource:
	return _lookup("waves", id)


func get_upgrade(id: String) -> Resource:
	return _lookup("upgrades", id)


func get_card(id: String) -> Resource:
	return _lookup("cards", id)


func get_mission(id: String) -> Resource:
	return _lookup("missions", id)


func get_product(id: String) -> Resource:
	return _lookup("shop", id)


func all_enemies() -> Array:
	return _all("enemies")


func all_towers() -> Array:
	return _all("towers")


func all_cards() -> Array:
	return _all("cards")


func all_upgrades() -> Array:
	return _all("upgrades")


func all_missions() -> Array:
	return _all("missions")


func all_products() -> Array:
	return _all("shop")


func _lookup(kind: String, id: String) -> Resource:
	var bucket: Dictionary = _by_kind.get(kind, {})
	return bucket.get(id, null)


func _all(kind: String) -> Array:
	var bucket: Dictionary = _by_kind.get(kind, {})
	return bucket.values()


func _load_directory(path: String) -> Dictionary:
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(path):
		push_warning("[ConfigDB] missing data directory: %s" % path)
		return result
	for file_name: String in DirAccess.get_files_at(path):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource: Resource = load(path.path_join(file_name))
		if resource == null:
			push_warning("[ConfigDB] failed to load %s/%s" % [path, file_name])
			continue
		var id := str(resource.get("id"))
		if id.is_empty():
			push_warning("[ConfigDB] resource without an id: %s/%s" % [path, file_name])
			continue
		if result.has(id):
			push_warning("[ConfigDB] duplicate id '%s' in %s" % [id, path])
			continue
		result[id] = resource
	return result
