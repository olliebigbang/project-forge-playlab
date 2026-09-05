extends SceneTree
const ARENA := preload("res://scripts/sunny_expedition/arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const WEAPON_LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
var imported_library_root := ""
var imported_library_key := ""
var directory := ""
var records: Array[Dictionary] = []

func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(key)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--library-root="): imported_library_root = arg.trim_prefix("--library-root=")
		if arg.begins_with("--library-key="): imported_library_key = arg.trim_prefix("--library-key=")
	directory = "res://.tools/sunny-motion/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	var library := LIBRARY.new(); library.style_id = "sunny_v1"
	var entries := library.load_all(false)
	if not imported_library_root.is_empty():
		var source_store := WEAPON_LIBRARY.new(); source_store.root_path = imported_library_root
		entries = source_store.load_entries()
		if not imported_library_key.is_empty(): entries = entries.filter(func(entry: Dictionary) -> bool: return entry.get("library_key", "") == imported_library_key)
		if entries.is_empty(): printerr("MOTION_IMPORTED_LIBRARY_EMPTY"); quit(2); return
	var arena := ARENA.new(); root.add_child(arena); arena.audio_enabled = false
	for w: int in range(entries.size()):
		for face: float in [1, -1]:
			for charge: bool in [false, true]:
				if not entries[w].get("ranged_runtime_profile", {}).is_empty() and charge: continue
				arena.begin_chapter(0, 14, entries[w], 100, 2); arena.set_process(false)
				arena.enemies.clear(); arena.spawn_clock = 100; arena.spawn_tells.clear()
				arena.player_position = Vector2(640, 500); arena.facing = face
				var sheet := Image.create(6 * 320, 10 * 220, false, Image.FORMAT_RGBA8)
				sheet.fill(Color("f9e5b1"))
				var count := 0
				var queued := {}
				var title := "%d-%d-%s" % [w, int(face), "charge" if charge else "combo"]
				for step: int in range(600):
					var controller: RefCounted = arena.melee_runtime.controller
					arena.set_touch_attack(charge and step < 65)
					if step == 0 or (not charge and controller.phase == "recovery" and controller.phase_duration - controller.phase_elapsed < 0.07 and not queued.has(controller.attack_serial)):
						arena.request_touch_attack()
						if step != 0: queued[controller.attack_serial] = true
					arena._process(1.0 / 60); arena.player_position = Vector2(640, 500); arena.facing = face
					if step % 10 != 0: continue
					arena.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
					var img := root.get_texture().get_image()
					if count in [0, 4, 7, 10]: img.save_png(directory.path_join("%s-%03d-full.png" % [title, count]))
					var crop := img.get_region(Rect2i(480, 330, 320, 220))
					crop.save_png(directory.path_join("%s-%03d.png" % [title, count]))
					sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((count % 6) * 320, (count / 6) * 220))
					var p: Dictionary = arena._attachment()
					var contact_pixels := {}
					for pixel: Dictionary in arena.melee_frame.get("pixels", []): contact_pixels[Vector2(pixel.position)] = true
					var contacts_drawn := true
					for point: Vector2 in arena.melee_frame.get("contacts", []): contacts_drawn = contacts_drawn and contact_pixels.has(point)
					records.append({"sample": title, "identity": entries[w].identity, "library_key": entries[w].get("library_key", ""), "frame": count, "step": step, "phase": controller.phase, "combo": controller.combo_index, "attack_serial": controller.attack_serial, "kind": controller.attack_kind, "clip": p.frame.key, "source_frame": p.frame.index, "angle": p.angle, "front_reach": Vector2(p.hand).distance_to(p.shoulder), "source_reach": float(p.front_frame.primary.reach) * 3, "hand": p.hand, "shoulder": p.shoulder, "support": p.support, "source_grip": arena.asset.grip_primary, "source_strike": arena.asset.tip, "source_effect_origin": arena.asset.muzzle, "anchor_source": arena.asset.anchor_source, "orientation_flipped": arena.asset.orientation_flipped})
					records[-1].merge({"state_power": arena.melee_runtime.state_power(), "active": arena.melee_runtime.active(), "contacts": arena.melee_frame.get("contacts", []).size(), "contacts_are_drawn_pixels": contacts_drawn, "field_points": arena.melee_frame.get("field", []).size(), "runtime_error": arena.melee_runtime.error, "deformation_roles": arena.melee_frame.get("geometry", {}).keys()})
					count += 1
				sheet.save_png(directory.path_join(title + "-sheet.png"))
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Continuous normal combo/held charge visual sampling, enemies disabled; not campaign playtest", "real_gpu": true, "online_calls":0, "samples":records}, "  "))
	print("SUNNY_MOTION_EVIDENCE ", ProjectSettings.globalize_path(directory))
	arena.free(); quit(0)
