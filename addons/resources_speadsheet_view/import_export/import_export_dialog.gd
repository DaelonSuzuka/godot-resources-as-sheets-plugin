tool
extends WindowDialog

export var prop_list_item_scene : PackedScene

onready var editor_view := $"../.."
onready var node_filename_options := $"TabContainer/Import/MarginContainer/ScrollContainer/VBoxContainer/GridContainer/OptionButton"
onready var node_classname_field := $"TabContainer/Import/MarginContainer/ScrollContainer/VBoxContainer/GridContainer/LineEdit"
onready var node_filename_props := $"TabContainer/Import/MarginContainer/ScrollContainer/VBoxContainer/GridContainer/OptionButton"
onready var prop_list := $"TabContainer/Import/MarginContainer/ScrollContainer/VBoxContainer"

var entries := []

var property_used_as_filename := 0
var import_data : SpreadsheetImport


func _on_FileDialogText_file_selected(path : String):
	import_data = SpreadsheetImport.new()
	import_data.initialize(path)

	_open_dialog()
	popup_centered()


func _open_dialog():
	node_classname_field.text = TextEditingUtils\
		.string_snake_to_naming_case(import_data.edited_path.get_file().get_basename())\
		.replace(" ", "")
	import_data.script_classname = node_classname_field.text

	_load_entries()
	_load_property_names()
	_create_prop_editors()


func _load_entries():
	var file = File.new()
	file.open(import_data.edited_path, File.READ)

	import_data.delimeter = ";"
	var text_lines := [file.get_line().split(import_data.delimeter)]
	var space_after_delimeter = false
	var line = text_lines[0]
	if line.size() == 1:
		import_data.delimeter = ","
		line = line[0].split(import_data.delimeter)
		text_lines[0] = line
		if line[1].begins_with(" "):
			for i in line.size():
				line[i] = line[i].trim_prefix(" ")
			
			text_lines[0] = line
			space_after_delimeter = true
			import_data.delimeter = ", "

	while !file.eof_reached():
		line = file.get_csv_line(import_data.delimeter[0])
		if space_after_delimeter:
			for i in line.size():
				line[i] = line[i].trim_prefix(" ")

		if line.size() == text_lines[0].size():
			text_lines.append(line)

		elif line.size() != 1:
			line.resize(text_lines[0].size())
			text_lines.append(line)

	entries = []
	entries.resize(text_lines.size())

	for i in entries.size():
		entries[i] = text_lines[i]


func _load_property_names():
	import_data.prop_names = Array(entries[0])
	import_data.prop_types.resize(import_data.prop_names.size())
	import_data.prop_types.fill(4)
	for i in import_data.prop_names.size():
		import_data.prop_names[i] = entries[0][i].replace(" ", "_").to_lower()
		if entries[1][i].is_valid_integer():
			import_data.prop_types[i] = SpreadsheetImport.PropType.INT

		elif entries[1][i].is_valid_float():
			import_data.prop_types[i] = SpreadsheetImport.PropType.REAL
				
		elif entries[1][i].begins_with("res://"):
			import_data.prop_types[i] = SpreadsheetImport.PropType.OBJECT

		else: import_data.prop_types[i] = SpreadsheetImport.PropType.STRING
	
	node_filename_options.clear()
	for i in import_data.prop_names.size():
		node_filename_options.add_item(import_data.prop_names[i], i)


func _create_prop_editors():
	for x in prop_list.get_children():
		if !x is GridContainer: x.free()

	for i in import_data.prop_names.size():
		var new_node = prop_list_item_scene.instance()
		prop_list.add_child(new_node)
		new_node.display(import_data.prop_names[i], import_data.prop_types[i])
		new_node.connect_all_signals(self, i)


func _generate_class():
	var new_script = GDScript.new()
	if import_data.script_classname != "":
		new_script.source_code = "class_name " + import_data.script_classname + " \nextends Resource\n\n"

	else:
		new_script.source_code = "extends Resource\n\n"
	
	# Enums
	var uniques = {}
	import_data.uniques = uniques
	for i in import_data.prop_types.size():
		if import_data.prop_types[i] == SpreadsheetImport.PropType.ENUM:
			var cur_value := ""
			uniques[i] = {}
			for j in entries.size():
				if j == 0 && import_data.remove_first_row: continue

				cur_value = entries[j][i].replace(" ", "_").to_upper()
				if cur_value == "":
					cur_value = "N_A"
				
				if !uniques[i].has(cur_value):
					uniques[i][cur_value] = uniques[i].size()
			
			new_script.source_code += import_data.create_enum_for_prop(i)
	
	# Properties
	for i in import_data.prop_names.size():
		new_script.source_code += import_data.create_property_line_for_prop(i)

	ResourceSaver.save(import_data.edited_path.get_basename() + ".gd", new_script)
	new_script.reload()
	
	# Because when instanced, objects have a copy of the script
	import_data.new_script = load(import_data.edited_path.get_basename() + ".gd")


func _export_tres_folder():
	var dir = Directory.new()
	dir.make_dir_recursive(import_data.edited_path.get_basename())

	import_data.prop_used_as_filename = import_data.prop_names[property_used_as_filename]
	var new_res : Resource
	for i in entries.size():
		if import_data.remove_first_row && i == 0:
			continue
	
		new_res = import_data.strings_to_resource(entries[i])
		ResourceSaver.save(new_res.resource_path, new_res)


func _on_Ok_pressed():
	hide()
	_generate_class()
	_export_tres_folder()
	yield(get_tree(), "idle_frame")
	editor_view.display_folder(import_data.edited_path.get_basename() + "/")
	yield(get_tree(), "idle_frame")
	editor_view.refresh()


func _on_OkSafe_pressed():
	hide()
	_generate_class()
	import_data.save()
	yield(get_tree(), "idle_frame")
	editor_view.display_folder(import_data.resource_path)
	yield(get_tree(), "idle_frame")
	editor_view.refresh()


# Input controls
func _on_classname_field_text_changed(new_text : String):
	import_data.script_classname = new_text.replace(" ", "")


func _on_remove_first_row_toggled(button_pressed : bool):
	import_data.remove_first_row = button_pressed


func _on_filename_options_item_selected(index):
	property_used_as_filename = index


func _on_list_item_type_selected(type : int, index : int):
	import_data.prop_types[index] = type
	

func _on_list_item_name_changed(name : String, index : int):
	import_data.prop_names[index] = name.replace(" ", "")
