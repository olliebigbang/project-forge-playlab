extends SceneTree

## Write the three material impact tones to disk so a person can listen to them.
##
## Calls the same `ImpactFeedbackProfile.synthesise` the game calls, so what comes out of
## the speakers here is what comes out of them in play. An axis whose three values a
## listener cannot tell apart is not an axis, and that is cheaper to find out now than in
## a twenty-round forced-choice run.
##
## Usage:
##     godot --headless --path <repo> --script res://tools/combat_feel/export_impact_tones.gd

const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const MIX_RATE := 22050
const TONES: PackedStringArray = ["forge_impact_dead", "forge_impact_ring", "forge_impact_soft"]
const OUTPUT_DIR := "res://artifacts/impact_tones"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for tone: String in TONES:
		var samples := FEEDBACK.synthesise(tone, MIX_RATE)
		var path := "%s/%s.wav" % [OUTPUT_DIR, tone]
		_write_wav(path, samples)
		print("%s  %d samples  %.3fs" % [tone, samples.size() / 2, float(samples.size() / 2) / float(MIX_RATE)])
	quit(0)


## Minimal 16-bit mono PCM container around the samples the game already produces.
func _write_wav(path: String, samples: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + path)
		return
	var data_size := samples.size()
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(MIX_RATE)
	file.store_32(MIX_RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	file.store_buffer(samples)
	file.close()
