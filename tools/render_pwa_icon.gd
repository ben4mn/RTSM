extends SceneTree

const ICON_SIZE: int = 192


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2:
		_fail("Expected SVG input and PNG output paths")
		return
	var svg: String = FileAccess.get_file_as_string(arguments[0])
	if svg.is_empty():
		_fail("Cannot read the PWA icon SVG")
		return
	var original: Image = Image.new()
	if original.load_svg_from_string(svg) != OK or original.get_width() <= 0 or original.get_width() != original.get_height():
		_fail("The PWA icon must be a valid square SVG")
		return
	var rendered: Image = Image.new()
	var scale: float = float(ICON_SIZE) / float(original.get_width())
	if rendered.load_svg_from_string(svg, scale) != OK or rendered.get_size() != Vector2i(ICON_SIZE, ICON_SIZE):
		_fail("Cannot render the PWA icon at 192 pixels")
		return
	if rendered.save_png(arguments[1]) != OK:
		_fail("Cannot save the PWA icon PNG")
		return
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
