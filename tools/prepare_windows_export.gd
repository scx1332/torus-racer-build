extends SceneTree
## Cross-platform output setup: do not depend on Unix mkdir syntax on Windows.


func _initialize() -> void:
	var output := ProjectSettings.globalize_path("res://build/windows")
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		push_error("Cannot create export output directory: " + error_string(error))
		quit(1)
		return
	var ignore_path := ProjectSettings.globalize_path("res://build/.gdignore")
	if not FileAccess.file_exists(ignore_path):
		var ignore := FileAccess.open(ignore_path, FileAccess.WRITE)
		if ignore == null:
			push_error("Cannot exclude generated builds from Godot's resource scan.")
			quit(1)
			return
	quit()
