#----------------------------------------

class_name UPackRSBase

#----------------------------------------

# https://docs.unity3d.com/351/Documentation/Manual/YAMLSceneExample.html

#----------------------------------------
# Built in native importers
#
# https://docs.unity3d.com/Manual/BuiltInImporters.html
#
# AssemblyDefinitionImporter              asmdef
# AssemblyDefinitionReferenceImporter     asmref
# AudioImporter                           ogg, aif, aiff, flac, wav, mp3, mod, it, s3m, xm
# ComputeShaderImporter                   compute
# DefaultImporter                         rsp, unity
# FBXImporter                             fbx, mb, ma, max, jas, dae, dxf, obj, c4d, blend, lxo
# IHVImageFormatImporter                  astc, dds, ktx, pvr
# LocalizationImporter                    po
# Mesh3DSImporter                         3ds
# NativeFormatImporter                    anim, animset, asset, blendtree, buildreport, colors, controller, cubemap
#                                         , curves, curvesNormalized, flare, fontsettings, giparams, gradients, guiskin, ht, mask, mat, mesh
#                                         , mixer, overrideController, particleCurves, particleCurvesSigned, particleDoubleCurves
#                                         , particleDoubleCurvesSigned, physicMaterial, physicsMaterial2D, playable, preset, renderTexture
#                                         , shadervariants, spriteatlas, state, statemachine, texture2D, transition, webCamTexture, brush, terrainlayer, signal
# PackageManifestImporter                 json
# PluginImporter                          dll, winmd, so, jar, java, kt, aar, suprx, prx, rpl, cpp, cc, c, h, jslib, jspre, bc, a, m, mm, swift, xib, bundle, dylib, config
# PrefabImporter                          prefab
# RayTracingShaderImporter                raytrace
# ShaderImporter                          cginc, cg, glslinc, hlsl, shader
# SketchUpImporter                        skp
# SpeedTreeImporter                       spm, st
# SubstanceImporter                       .sbsar
# TextScriptImporter                      txt, html, htm, xml, json, csv, yaml, bytes, fnt, manifest, md, js, boo, rsp
# TextureImporter                         jpg, jpeg, tif, tiff, tga, gif, png, psd, bmp, iff, pict, pic, pct, exr, hdr
# TrueTypeFontImporter                    ttf, dfont, otf, ttc
# VideoClipImporter                       avi, asf, wmv, mov, dv, mp4, m4v, mpg, mpeg, ogv, vp8, webm
# VisualEffectImporter                    vfx, vfxoperator, vfxblock
#----------------------------------------

var package_path: String
var catalog: Dictionary
var debug_log: bool
var unitypackage_util: String
var enable_disk_storage: bool = false
var enable_memcache: bool = false
var upack_config: UPackConfig

#----------------------------------------

static func call_only_once():
	print("UPackRS::CallOnlyOnce::RegisterPivotFixer")
	GLTFDocument.register_gltf_document_extension(PivotFixer.new(), true)

#----------------------------------------

func directories() -> PackedStringArray:
	if catalog == null || catalog.is_empty():
		push_error("UPackRS::_directories::NotReady")
		return []

	var dir_only = func(guid) -> bool:
		return catalog[guid].asset_meta[0].folderAsset == true

	var to_pathname = func(guid) -> String:
		return catalog[guid].pathname

	var dirs: PackedStringArray = (catalog
		.keys()
		.filter(dir_only)
		.map(to_pathname))

	dirs.sort()
	return dirs

#----------------------------------------

# callback(UPackRS, dir_path: String, files: Array)

func files(dir_path: String, callback: Callable = Callable()) -> Array:
	if callback.is_valid():
		WorkerThreadPool.add_task(func():
			var dirs = _files(dir_path)
			callback.call_deferred(self, dir_path, dirs)
		)
		return []
	else:
		return _files(dir_path)

#----------------------------------------

func _files(dir_path: String) -> Array:
	if catalog == null || catalog.is_empty():
		push_error("UPackRS::_directory_list::NotReady")
		return []

	var dir_path_files_only = func (guid: String, dir_path: String) -> bool:
		if catalog[guid].pathname == null:
			return false
		var a = catalog[guid].pathname.begins_with(dir_path)
		var b = !catalog[guid].asset_meta[0].folderAsset
		return a && b

	var to_asset = func (guid) -> Dictionary:
		return catalog[guid]

	var contents: Array = (catalog
		.keys()
		.filter(dir_path_files_only.bind(dir_path))
		.map(to_asset))

	var sort = func(a: Dictionary, b: Dictionary) -> bool:
		var a_name: String = a.pathname
		var b_name: String = b.pathname
		return a_name.casecmp_to(b_name) == 0

	contents.sort_custom(sort)
	return contents

#----------------------------------------

func package_extract_binary(guid: String, fbx2gltf: bool) -> PackedByteArray:
	var result = _util_execute([
		package_path,
		"extract",
		guid,
		# -f, --fbx2gltf
		# -b, --base64
		"-fb" if fbx2gltf else "-b"
	], [""])[0]
	return Marshalls.base64_to_raw(result)

#----------------------------------------

func package_extract_json(guid: String):
	return JSON.parse_string(_util_execute([
		package_path,
		"extract",
		guid,
		"-j"
	], [""])[0])

#----------------------------------------

func package_dump():
	var disk_path: String = "%s/%s/catalog.json" % [
		upack_config.extract_path,
		package_path.get_file().get_basename()
	]

	if upack_config.enable_disk_storage && FileAccess.file_exists(disk_path):
		var json = FileAccess.get_file_as_string(disk_path)
		return JSON.parse_string(json)

	var json = _package_dump()

	if upack_config.enable_disk_storage:
		DirAccess.make_dir_recursive_absolute(disk_path.get_base_dir())
		var file = FileAccess.open(disk_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(json))
			file.close()
		else:
			push_warning("UPackRS::PackageDump::FileOpenError::%s::%s" % [FileAccess.get_open_error(), disk_path])

	return json

#----------------------------------------

func _package_dump():
	var dump = _util_execute([
		package_path,
		"dump"
	], [""])[0]

	if dump == "":
		push_error("AssetUtilRS::PackageDump::DumpFailed")
		return null

	var json = JSON.parse_string(dump)
	if json == null:
		push_error("AssetUtilRS::PackageDump::JsonParseFailed")
		return null

	var copy_guid_ufile = func(guid: String, dict: Dictionary):
		var asset = dict[guid]
		asset._ufile_id = "%s:%s" % [guid, "_"]
		asset._guid = guid
		if asset.asset != null:
			asset.asset.map(func(asset):
				asset._guid = guid
				asset._ufile_id = "%s:%s" % [guid, asset._file_id]
			)

	(json
		.keys()
		.map(copy_guid_ufile.bind(json))
	)

	return json

#----------------------------------------

func _package_list(dir: String):
	return JSON.parse_string(_util_execute([
		package_path,
		"list",
		"--dir",
		dir
	], [""])[0])

#----------------------------------------

func _util_execute(arguments: PackedStringArray, default: Variant):
	print("UPackRS::UtilExecute::%s %s" % [unitypackage_util, " ".join(arguments)])
	var output = []
	var result = OS.execute(ProjectSettings.globalize_path(unitypackage_util), arguments, output)
	if result != 0:
		push_error("Error _util_execute %d: %s %s = %s" % [result, unitypackage_util, arguments, output])
		return default
	return output

#----------------------------------------

func _init(_package_path: String, _upack_config: UPackConfig):
	package_path = _package_path
	upack_config = _upack_config

	unitypackage_util = upack_config.unitypackage_util_path
	debug_log = upack_config.debug_log

	enable_disk_storage = upack_config.enable_disk_storage
	enable_memcache = upack_config.enable_memcache

	assert(FileAccess.file_exists(upack_config.unitypackage_util_path), "unitypackage_util not found")
	assert(FileAccess.file_exists(upack_config.fbx2gltf_path), "fbx2gltf not found")

#----------------------------------------

func trace(message: String, color: Color = Color.VIOLET) -> void:
	if debug_log:
		print_rich("📦 [color=%s][UPackRS] %s[/color]" % [
			color.to_html(),
			message
		])

#----------------------------------------
