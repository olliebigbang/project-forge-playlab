extends "res://tests/run_tests.gd"

func _initialize() -> void:
	call_deferred("_run_compatibility")

func _run_compatibility() -> void:
	# Narrow, read-only legacy coverage. The historical full runner writes to
	# user:// and is not safe to use as this branch's isolated acceptance runner.
	_run("Training delegates to the same identity-agnostic renderer and clock", _test_open_identity_arena_contract)
	_run("Training effects remain gated: no implicit heal, burn or chain", _test_open_identity_effect_gates)
	print("TRAINING_MELEE_COMPATIBILITY passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
