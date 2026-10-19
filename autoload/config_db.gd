extends Node
## Loads every data resource into `id -> Resource` dictionaries at startup.
##
## Enemy, wave, tower, upgrade, card, mission, shop and meta-upgrade lookups are
## typed; data directories may be empty without breaking the boot.

const DATA_DIRS := {
	"enemies": "res://data/enemies",
	"towers": "res://data/towers",
	"waves": "res://data/waves",
	"upgrades": "res://data/upgrades",
	"meta_upgrades": "res://data/meta_upgrades",
	"cards": "res://data/cards",
	"missions": "res://data/missions",
	"shop": "res://data/shop",
	"monetization": "res://data/monetization",
}

var _by_kind: Dictionary = {}


func _ready() -> void:
	reload_all()


## Re-reads every data directory. Safe on empty folders.
func reload_all() -> void:
	_by_kind.clear()
	for kind: String in DATA_DIRS:
		_by_kind[kind] = _load_directory(DATA_DIRS[kind])


func get_enemy(id: String) -> EnemyData:
	return _lookup("enemies", id) as EnemyData


func get_tower(id: String) -> TowerData:
	return _lookup("towers", id) as TowerData


func get_wave_table(id := "main") -> WaveTable:
	return _lookup("waves", id) as WaveTable


func get_upgrade(id: String) -> UpgradeTrack:
	return _lookup("upgrades", id) as UpgradeTrack


## Permanent Gold upgrade track, or null.
func get_meta_upgrade(id: String) -> MetaUpgradeData:
	return _lookup("meta_upgrades", id) as MetaUpgradeData


func get_card(id: String) -> CardData:
	return _lookup("cards", id) as CardData


## Daily mission or achievement, or null.
func get_mission(id: String) -> MissionData:
	return _lookup("missions", id) as MissionData


## Shop product, or null.
func get_product(id: String) -> ShopProduct:
	return _lookup("shop", id) as ShopProduct


## Real ad/billing identifiers. Falls back to a fresh default resource so the
## disabled adapters can never crash on a missing file.
func get_store_config() -> StoreConfig:
	var config := _lookup("monetization", "main") as StoreConfig
	return config if config != null else StoreConfig.new()


func all_enemies() -> Array:
	return _all("enemies")


func all_towers() -> Array:
	return _all("towers")


func all_cards() -> Array:
	return _all("cards")


func all_upgrades() -> Array:
	return _all("upgrades")


## Every permanent upgrade, ordered by `order` for the Upgrades screen.
func all_meta_upgrades() -> Array[MetaUpgradeData]:
	var result: Array[MetaUpgradeData] = []
	for entry: Variant in _all("meta_upgrades"):
		var track := entry as MetaUpgradeData
		if track != null:
			result.append(track)
	result.sort_custom(func(a: MetaUpgradeData, b: MetaUpgradeData) -> bool: return a.order < b.order)
	return result


func all_missions() -> Array:
	return _all("missions")


## Only the rotating daily mission pool.
func all_daily_missions() -> Array[MissionData]:
	var result: Array[MissionData] = []
	for entry: Variant in _all("missions"):
		var mission := entry as MissionData
		if mission != null and mission.daily:
			result.append(mission)
	return result


## Only the persistent achievements.
func all_achievements() -> Array[MissionData]:
	var result: Array[MissionData] = []
	for entry: Variant in _all("missions"):
		var mission := entry as MissionData
		if mission != null and not mission.daily:
			result.append(mission)
	return result


## Every shop product, ordered by `order`.
func all_products() -> Array[ShopProduct]:
	var result: Array[ShopProduct] = []
	for entry: Variant in _all("shop"):
		var product := entry as ShopProduct
		if product != null:
			result.append(product)
	result.sort_custom(func(a: ShopProduct, b: ShopProduct) -> bool: return a.order < b.order)
	return result


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
