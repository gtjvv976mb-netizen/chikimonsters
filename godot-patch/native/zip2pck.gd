## Repack an extracted game pack as a Godot .pck (GDPC).
##
##   godot --headless --script zip2pck.gd -- <extracted-dir> <out.pck>
##
## The published iOS pack is a ZIP, which the web loader mounts as index.pcz. A native Godot app
## finds its main pack only as "<executable>.pck" and reads that name as GDPC — a ZIP there is
## refused — so the same files are written again in GDPC form. Byte-for-byte the same files.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <extracted-dir> <out.pck>")
		quit(2)
		return
	var root := String(args[0]).trim_suffix("/")
	var packer := PCKPacker.new()
	if packer.pck_start(args[1]) != OK:
		printerr("cannot write ", args[1])
		quit(1)
		return
	var n := _add(packer, root, root)
	if packer.flush(false) != OK:
		printerr("flush failed")
		quit(1)
		return
	print("packed %d files into %s" % [n, args[1]])
	quit(0)


func _add(packer: PCKPacker, root: String, dir: String) -> int:
	var n := 0
	var d := DirAccess.open(dir)
	d.include_hidden = true
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			n += _add(packer, root, full)
		else:
			var rel := full.substr(root.length() + 1)
			if packer.add_file("res://" + rel, full) != OK:
				printerr("add failed: ", rel)
			n += 1
		name = d.get_next()
	return n
