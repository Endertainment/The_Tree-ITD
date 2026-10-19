class_name SaveMigrations
extends RefCounted
## Version migrations for the save file.
##
## Each migration is a pure function: it takes a dictionary and returns a new
## dictionary at the next version. Unknown keys are always preserved, because
## a newer build of the game may own data this build does not understand.

const CURRENT_VERSION := SaveDefaults.CURRENT_VERSION


## Migrates `data` up to the current save version.
static func migrate(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var version: int = int(out.get("version", 0))
	if version <= 0:
		push_warning("[SaveMigrations] save has no version; starting a fresh profile")
		return SaveDefaults.create()
	if version > CURRENT_VERSION:
		push_warning("[SaveMigrations] save v%d is newer than v%d; loading it as-is" % [version, CURRENT_VERSION])
		return out
	# Future steps plug in here, e.g.:
	#   if version == 1:
	#       out = _migrate_v1_to_v2(out)
	#   version = 2
	# v1 is the first shipped schema, so there is nothing to do yet.
	out["version"] = CURRENT_VERSION
	return out
