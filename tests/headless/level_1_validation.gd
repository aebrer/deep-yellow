extends SceneTree
## File-level headless smoke validation for PR 75 Level 1 framework.
##
## This intentionally avoids instantiating project classes because Godot --script
## compiles outside the normal autoload-global context. Use this together with:
##   godot --headless --import
##   godot --headless --quit
##
## Run: godot --headless --script tests/headless/level_1_validation.gd

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_file_exists("res://scripts/procedural/level_1_generator.gd")
	_check_file_exists("res://scripts/resources/level_01_config.gd")
	_check_file_exists("res://assets/levels/level_01/level_01_config.tres")
	_check_file_exists("res://assets/level_01_mesh_library.tres")

	_validate_stair_framework()
	_validate_level_1_registration()
	_validate_water_semantics()
	_validate_level_1_content()
	_validate_generators()
	_validate_visual_assets()

	if _failures.is_empty():
		print("Level 1 file validation passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _check_file_exists(path: String) -> void:
	_check(FileAccess.file_exists(path), "Missing file: %s" % path)

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_failures.append("Could not read file: %s" % path)
		return ""
	return file.get_as_text()

func _contains(path: String, needle: String) -> bool:
	return _read(path).find(needle) >= 0

func _validate_stair_framework() -> void:
	_check(_contains("res://scripts/resources/entity_info.gd", "exit_destination_level_id"), "EntityInfo should define exit_destination_level_id")
	_check(_contains("res://scripts/world/world_entity.gd", "exit_destination_level_id"), "WorldEntity should persist exit_destination_level_id")
	_check(_contains("res://scripts/autoload/entity_registry.gd", "tutorial_to_lobby_stairs"), "EntityRegistry should define tutorial_to_lobby_stairs")
	_check(_contains("res://scripts/autoload/entity_registry.gd", "lobby_to_poolrooms_stairs"), "EntityRegistry should define lobby_to_poolrooms_stairs")
	_check(_contains("res://scripts/autoload/entity_registry.gd", "poolrooms_to_lobby_stairs"), "EntityRegistry should define poolrooms_to_lobby_stairs")
	_check(_contains("res://scripts/procedural/chunk_manager.gd", "func get_exit_entity_at_tile"), "ChunkManager should expose explicit exit entity lookup")
	_check(_contains("res://scripts/player/states/post_turn_state.gd", "get_exit_entity_at_tile"), "PostTurnState should resolve destination from stair entity")
	_check(not _contains("res://scripts/player/states/post_turn_state.gd", "destinations[0]"), "PostTurnState must not use exit_destinations[0]")

func _validate_level_1_registration() -> void:
	_check(_contains("res://scripts/autoload/level_manager.gd", "level_01/level_01_config.tres"), "LevelManager should preload Level 1 config")
	_check(_contains("res://scripts/autoload/level_manager.gd", "[-1, 0, 1]"), "LevelManager known levels should include 1")
	_check(_contains("res://scripts/procedural/chunk_manager.gd", "Level1Generator.new()"), "ChunkManager should register Level1Generator")
	_check(_contains("res://scripts/procedural/chunk_manager.gd", "Level1Config.new()"), "ChunkManager should register Level1Config")
	_check(_contains("res://scripts/resources/level_00_config.gd", "exit_destinations = [1]"), "Level 0 should allow/preload implemented Level 1 destination")

func _validate_water_semantics() -> void:
	_check(_contains("res://scripts/procedural/sub_chunk.gd", "FLOOR_SHALLOW_WATER = 15"), "SubChunk should define shallow water as floor variant")
	_check(_contains("res://scripts/procedural/sub_chunk.gd", "DEEP_WATER = 26"), "SubChunk should define deep water as blocked variant")
	_check(_contains("res://scripts/procedural/sub_chunk.gd", "is_shallow_water_type"), "SubChunk should expose shallow-water helper")
	_check(_contains("res://scripts/procedural/sub_chunk.gd", "is_deep_water_type"), "SubChunk should expose deep-water helper")
	_check(_contains("res://scripts/resources/level_01_config.gd", "15: 3"), "Level1Config should map shallow water to mesh item")
	_check(_contains("res://scripts/resources/level_01_config.gd", "26: 4"), "Level1Config should map deep water to mesh item")

func _validate_level_1_content() -> void:
	var config := _read("res://scripts/resources/level_01_config.gd")
	_check(config.find("exit_destinations = [0]") >= 0, "Level 1 should only list implemented return destination")
	_check(config.find("\"sodden\"") >= 0, "Level 1 spawn table should include sodden")
	_check(config.find("\"drowner\"") >= 0, "Level 1 spawn table should include drowner")
	_check(config.find("\"ambassador\"") >= 0, "Level 1 spawn table should include ambassador")
	_check(config.find("AlmondWater.new()") >= 0, "Level 1 item pool should include Almond Water")
	_check(_contains("res://scripts/ai/behaviors/behavior_registry.gd", "_SoddenBehavior"), "BehaviorRegistry should preload Sodden behavior")
	_check(_contains("res://scripts/ai/behaviors/behavior_registry.gd", "_DrownerBehavior"), "BehaviorRegistry should preload Drowner behavior")
	_check(_contains("res://scripts/ai/behaviors/behavior_registry.gd", "_AmbassadorBehavior"), "BehaviorRegistry should preload Ambassador behavior")
	_check(_contains("res://scripts/world/entity_renderer.gd", "\"sodden\""), "EntityRenderer should have sodden visual config")
	_check(_contains("res://scripts/world/entity_renderer.gd", "\"drowner\""), "EntityRenderer should have drowner visual config")
	_check(_contains("res://scripts/world/entity_renderer.gd", "\"ambassador\""), "EntityRenderer should have ambassador visual config")

func _validate_generators() -> void:
	var level1 := _read("res://scripts/procedural/level_1_generator.gd")
	_check(level1.find("class_name Level1Generator") >= 0, "Level1Generator should exist")
	_check(level1.find("SHALLOW_WATER") >= 0, "Level1Generator should place shallow water")
	_check(level1.find("DEEP_WATER") >= 0, "Level1Generator should place deep water")
	_check(level1.find("_build_room_grid") >= 0, "Level1Generator should build room architecture")
	_check(level1.find("poolrooms_to_lobby_stairs") >= 0, "Level1Generator should place explicit return stairs")
	_check(level1.find("Level2") < 0 and level1.find("level 2") < 0, "Level1Generator should not expose Level 2 stairs")
	_check(_contains("res://scripts/procedural/level_neg1_generator.gd", "tutorial_to_lobby_stairs"), "Tutorial generator should place explicit tutorial route")
	_check(_contains("res://scripts/procedural/level_0_generator.gd", "lobby_to_poolrooms_stairs"), "Level 0 generator should place explicit poolrooms route")
	_check(_contains("res://scripts/procedural/chunk_manager.gd", "_cut_border_hallways"), "ChunkManager should have border hallway cutting for connectivity")

func _validate_visual_assets() -> void:
	_check(_contains("res://assets/level_01_mesh_library.tres", "ShallowWater"), "Level 1 mesh library should include shallow water")
	_check(_contains("res://assets/level_01_mesh_library.tres", "DeepWater"), "Level 1 mesh library should include deep water")
	_check(_contains("res://assets/levels/level_01/floor_tile.tres", "psx_lit.gdshader"), "Level 1 floor material should use PSX lit shader")
	_check(_contains("res://assets/levels/level_01/wall_tile.tres", "psx_wall_proximity.gdshader"), "Level 1 wall material should use proximity shader")
	_check(_contains("res://assets/levels/level_01/ceiling_tile.tres", "psx_ceiling_proximity.gdshader"), "Level 1 ceiling material should use ceiling proximity shader")
	_check(FileAccess.file_exists("res://assets/textures/levels/level_01/floor_tile.png"), "Floor tile texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/levels/level_01/wall_tile.png"), "Wall tile texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/levels/level_01/ceiling_tile.png"), "Ceiling tile texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/levels/level_01/water_surface.png"), "Water surface texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/entities/sodden.png"), "Sodden entity texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/entities/drowner.png"), "Drowner entity texture should exist")
	_check(FileAccess.file_exists("res://assets/textures/entities/ambassador.png"), "Ambassador entity texture should exist")
