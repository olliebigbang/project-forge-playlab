class_name FirearmVisualCachePolicy
extends RefCounted

const CURRENT_PIPELINE_VERSION := "fal-gpt-image-1.5-image2pixel24-anthropic-identity-v5"
const LEGACY_PIPELINE_VERSIONS: PackedStringArray = [
	"fal-gpt-image-1.5-image2pixel24-anthropic-identity-v3",
]
const CACHE_SCHEMA := "forge-fal-firearm-visual-cache-v1"
const MANIFEST_SCHEMA := "forge-fal-firearm-visual-manifest-v1"
const VERIFICATION_SCHEMA := "forge-firearm-ai-visual-verification-v1"
const GATE_SCHEMA := "forge-firearm-visual-identity-gate-v2"


static func evidence_errors(
	record: Dictionary,
	manifest: Dictionary,
	sprite_bytes: PackedByteArray,
	expected_key: String = "",
	allow_legacy: bool = true
) -> PackedStringArray:
	var errors := PackedStringArray()
	if str(record.get("schema", "")) != CACHE_SCHEMA:
		errors.append("FIREARM_VISUAL_CACHE_SCHEMA_INVALID")
	if str(record.get("key", "")).is_empty():
		errors.append("FIREARM_VISUAL_CACHE_KEY_MISSING")
	if not expected_key.is_empty() and str(record.get("key", "")) != expected_key:
		errors.append("FIREARM_VISUAL_CACHE_KEY_MISMATCH")
	var pipeline := str(record.get("pipeline_version", ""))
	if pipeline != CURRENT_PIPELINE_VERSION and (not allow_legacy or pipeline not in LEGACY_PIPELINE_VERSIONS):
		errors.append("FIREARM_VISUAL_CACHE_PIPELINE_STALE")
	if str(manifest.get("schema", "")) != MANIFEST_SCHEMA:
		errors.append("FIREARM_VISUAL_MANIFEST_SCHEMA_INVALID")
	if str(manifest.get("status", "")) != "success":
		errors.append("FIREARM_VISUAL_MANIFEST_NOT_SUCCESS")
	for flag: String in ["finished_art", "presentable_to_player", "firearm_visual_gate_passed"]:
		if not bool(manifest.get(flag, false)):
			errors.append("FIREARM_VISUAL_MANIFEST_FLAG_MISSING:%s" % flag)
	var verification := manifest.get("ai_visual_identity_verification", {}) as Dictionary
	if (
		str(verification.get("schema", "")) != VERIFICATION_SCHEMA
		or not bool(verification.get("ok", false))
		or not bool(verification.get("passed", false))
	):
		errors.append("FIREARM_VISUAL_AI_IDENTITY_VERIFICATION_MISSING")
	var expected_hash := str(record.get("processed_sprite_sha256", ""))
	if sprite_bytes.is_empty() or expected_hash.is_empty() or _sha256(sprite_bytes) != expected_hash:
		errors.append("FIREARM_VISUAL_CACHE_SPRITE_HASH_MISMATCH")
	if pipeline == CURRENT_PIPELINE_VERSION:
		errors.append_array(current_gate_errors(manifest))
	return errors


static func current_gate_errors(manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var gate := manifest.get("firearm_visual_identity_gate", {}) as Dictionary
	var anchors := gate.get("anchors", {}) as Dictionary
	if str(gate.get("schema", "")) != GATE_SCHEMA:
		errors.append("FIREARM_VISUAL_CURRENT_GATE_MISSING")
	if not bool(gate.get("ok", false)) or not bool(gate.get("action_anchor_contract", false)):
		errors.append("FIREARM_VISUAL_ACTION_ANCHOR_CONTRACT_MISSING")
	for anchor: String in ["GripPrimary", "GripSecondary", "Muzzle", "FeedCenter", "ActionCycle", "ActionReload"]:
		var value: Variant = anchors.get(anchor, [])
		if not value is Array or (value as Array).size() < 2:
			errors.append("FIREARM_VISUAL_ACTION_ANCHOR_MISSING:%s" % anchor)
	return errors


static func upgraded_record(record: Dictionary, key: String, sprite_bytes: PackedByteArray) -> Dictionary:
	var upgraded := record.duplicate(true)
	upgraded["schema"] = CACHE_SCHEMA
	upgraded["key"] = key
	upgraded["pipeline_version"] = CURRENT_PIPELINE_VERSION
	upgraded["processed_sprite_sha256"] = _sha256(sprite_bytes)
	upgraded["locally_revalidated_from_pipeline"] = str(record.get("pipeline_version", ""))
	upgraded["remote_generation_used_for_migration"] = false
	return upgraded


static func upgraded_manifest(manifest: Dictionary, gate: Dictionary, key: String) -> Dictionary:
	var upgraded := manifest.duplicate(true)
	upgraded["firearm_visual_identity_gate"] = gate.duplicate(true)
	upgraded["firearm_visual_gate_passed"] = true
	upgraded["finished_art"] = true
	upgraded["presentable_to_player"] = true
	upgraded["cache"] = {
		"schema": CACHE_SCHEMA,
		"hit": true,
		"key": key,
		"pipeline_version": CURRENT_PIPELINE_VERSION,
		"locally_revalidated": true,
		"remote_generation_used": false,
	}
	return upgraded


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
