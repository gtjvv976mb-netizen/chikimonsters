## GPU TEXTURES for the phone: rewrite the game's WebP textures as ASTC 4x4.
##
##   godot --headless --script astc-pack.gd -- <extracted-pack-dir> [shard] [shards]
##
## The web build stores its art as WebP inside each .ctex, the smallest download. A phone has to
## decode every one of those on the CPU the first time it is drawn (a hitch), and keeps it in GPU
## memory at 4 bytes a pixel. ASTC 4x4 is what Apple GPUs read directly: 1 byte a pixel, and
## loading it is a copy, so no decode hitch and a quarter of the memory. Same art, same size.
##
## Converted: RGB8 / RGBA8 WebP textures without mipmaps whose sides are multiples of 4 and at
## least 32 px (the ASTC block is 4x4, so their size is unchanged). Everything else is left as it
## is. The game's scripts that read texture pixels decompress first (ChikFeat.plain_image).
## Also left alone: the card art named in card-presentation-v4/export-bindings.json, whose .ctex
## bytes the card presenter checks against a SHA-256 before it trims the card exteriors.
## Each file is written beside the original and renamed over it, so a killed shard never leaves a
## half-written texture. A texture that should convert but fails to (decode, compress or write)
## counts as a failure, and any failure makes the process exit 1.
## Runs the editor binary (only the editor has the compressor); `shard`/`shards` split the work
## across processes, since each image is compressed on one thread.
extends SceneTree

const DATA_FORMAT_IMAGE := 0
const DATA_FORMAT_WEBP := 2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <extracted-pack-dir> [shard] [shards]")
		quit(2)
		return
	var root := String(args[0]).trim_suffix("/")
	var shard := int(args[1]) if args.size() > 1 else 0
	var shards := int(args[2]) if args.size() > 2 else 1
	var files: PackedStringArray = []
	_collect(root.path_join(".godot/imported"), files)
	files.sort()
	var keep := _bound_cards(root)
	var done := 0
	var skipped := 0
	var bound := 0
	var before := 0
	var after := 0
	var t0 := Time.get_ticks_msec()
	for i in files.size():
		if i % shards != shard:
			continue
		if keep.has(files[i].get_file()):
			bound += 1
			continue
		var r := _convert(files[i])
		if r.is_empty():
			skipped += 1
		elif r[0] < 0:
			_failed += 1
			printerr("astc failed: %s (%s)" % [files[i].get_file(), r[1]])
		else:
			done += 1
			before += r[0]
			after += r[1]
	print("astc shard %d/%d: %d converted (%.0f MB of pixels -> %.0f MB), %d left as they were, %d bound cards kept, %d failed, %.0f s" % [
		shard, shards, done, before / 1048576.0, after / 1048576.0, skipped, bound, _failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if _failed > 0 else 0)


var _failed := 0


## file names of the imported card textures whose bytes ChikiseumCardPresentation verifies
func _bound_cards(root: String) -> Dictionary:
	var out := {}
	var path := root.path_join("card-presentation-v4/export-bindings.json")
	if not FileAccess.file_exists(path):
		return out
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.get("entries") is Dictionary:
		for e in d.entries.values():
			if e is Dictionary:
				var p := String(e.get("imported_ctex_path", ""))
				if not p.is_empty():
					out[p.get_file()] = true
	if out.is_empty():
		printerr("astc: export-bindings.json lists no card textures")
		_failed += 1
	return out


func _collect(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".ctex"):
			out.append(dir.path_join(f))


## [decoded bytes, ASTC bytes] when converted, [] when left alone, [-1, reason] on a failure
func _convert(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var header := f.get_buffer(36)  # "GST2", version, original w/h, flags, mip limit, 3 reserved
	if header.size() < 36 or header.slice(0, 4).get_string_from_ascii() != "GST2":
		return []
	var data_format := f.get_32()
	var w := f.get_16()
	var h := f.get_16()
	var mipmaps := f.get_32()
	var fmt := f.get_32()
	if data_format != DATA_FORMAT_WEBP or mipmaps != 0:
		return []
	if fmt != Image.FORMAT_RGB8 and fmt != Image.FORMAT_RGBA8:
		return []
	if w % 4 != 0 or h % 4 != 0 or w < 32 or h < 32:
		return []
	var size := f.get_32()
	var webp := f.get_buffer(size)
	f.close()
	var img := Image.new()
	if webp.size() != size or img.load_webp_from_buffer(webp) != OK or img.get_width() != w or img.get_height() != h:
		return [-1, "decode"]
	var decoded := img.get_data().size()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.compress(Image.COMPRESS_ASTC, Image.COMPRESS_SOURCE_GENERIC, Image.ASTC_FORMAT_4x4) != OK:
		return [-1, "compress"]
	if img.get_width() != w or img.get_height() != h:
		return [-1, "size"]
	var tmp := path + ".tmp"
	var out := FileAccess.open(tmp, FileAccess.WRITE)
	if out == null:
		return [-1, "open"]
	out.store_buffer(header)
	out.store_32(DATA_FORMAT_IMAGE)
	out.store_16(w)
	out.store_16(h)
	out.store_32(0)
	out.store_32(img.get_format())
	out.store_buffer(img.get_data())
	var werr := out.get_error()
	out.close()
	if werr != OK or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return [-1, "write"]
	return [decoded, img.get_data().size()]
