#----------------------------------------

# Interface for unitypackage-rs utility

class_name UPackRS extends UPackRSBase

#----------------------------------------

signal catalog_loaded
signal prefabs_loaded

#----------------------------------------

var progress: ProgressUpdates = ProgressUpdates.new()

#----------------------------------------

# callback(UPackRS, bool)

func load_catalog(callback: Callable = Callable()) -> bool:
	if callback.is_valid():
		WorkerThreadPool.add_task(func():
			var result = package_dump()
			if result == null:
				trace("LoadCatalog::PackageDumpFailed", Color.RED)
				callback.call_deferred(self, false)
			else:
				catalog = result
				trace("LoadCatalog::PackageDumpLoaded", Color.GREEN)
				callback.call_deferred(self, true)
			catalog_loaded.emit()
		)
		return false
	else:
		var result = package_dump()
		catalog_loaded.emit()
		if result == null:
			trace("LoadCatalog::PackageDumpFailed", Color.RED)
			return false
		else:
			catalog = result
			trace("LoadCatalog::PackageDumpLoaded", Color.GREEN)
			return true

#----------------------------------------

func get_asset_by_ref(file_ref: Dictionary) -> Asset:
	if !file_ref.has("guid"):
		push_error("UPackRS::AssetByRef::GuidMissing")
		return null

	var guid = file_ref.guid
	if not guid is String:
		push_error("UPackRS::AssetByRef::BadGuid")
		return null

	return get_asset(file_ref.guid)

#----------------------------------------

func get_asset(guid: String) -> Asset:
	if !catalog.has(guid):
		push_error("UPackRS::AssetNotFound::%s" % guid)
		return null

	var asset_data = catalog[guid]
	if asset_data.has("_memcache_asset"):
		return asset_data._memcache_asset

	var new_asset = Asset.new(self, asset_data)
	asset_data._memcache_asset = new_asset

	return asset_data._memcache_asset

#----------------------------------------

func get_asset_doc_by_ref(file_ref: Dictionary) -> AssetDoc:
	return get_asset_doc(file_ref.guid, file_ref.fileID)

func get_asset_doc(guid: String, file_id: int) -> AssetDoc:
	var asset = get_asset(guid)
	if asset == null:
		return null

	return asset.get_asset_doc_by_id(file_id)

#----------------------------------------

func build_all_prefabs(use_thread: bool):
	if false:
		return

	var prefab_worker = func():
		var is_prefab = func(asset: Asset):
			return asset.pathname.ends_with(".prefab")
		var build_prefab = func(asset: Asset):
			asset.asset_scene(null, null)
			progress.progress_tick(asset.pathname)

		var prefabs = (catalog
			.keys()
			.map(get_asset)
			.filter(is_prefab)
		)

		progress.progress_reset()
		progress.progress_add(prefabs.size(), "Prefabs")
		prefabs.map(build_prefab)
		prefabs_loaded.emit()

	var material_worker = func():
		var is_material = func(asset: Asset):
			return asset.pathname.ends_with(".mat")
		var build_prefab = func(asset: Asset):
			asset.asset_scene(null, null)
			progress.progress_tick(asset.pathname)

		var prefabs = (catalog
			.keys()
			.map(get_asset)
			.filter(is_material)
		)

		progress.progress_reset()
		progress.progress_add(prefabs.size(), "Prefabs")
		prefabs.map(build_prefab)
		prefabs_loaded.emit()

	var unity_worker = func():
		var is_material = func(asset: Asset):
			return asset.pathname.ends_with(".unity")
		var build_unity = func(asset: Asset):
			asset.asset_scene(null, null)
			progress.progress_tick(asset.pathname)

		var prefabs = (catalog
			.keys()
			.map(get_asset)
			.filter(is_material)
		)

		progress.progress_reset()
		progress.progress_add(prefabs.size(), "Prefabs")
		prefabs.map(build_unity)
		prefabs_loaded.emit()

	if use_thread:
		var thread = Thread.new()
		thread.start(prefab_worker, Thread.PRIORITY_HIGH)
		#print("waiting for task")
		#WorkerThreadPool.wait_for_task_completion(task)
	else:
		material_worker.call()
		prefab_worker.call()
		#unity_worker.call()

#----------------------------------------
