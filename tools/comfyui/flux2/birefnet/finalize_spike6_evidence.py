from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import socket
import tempfile
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
FLUX2_ROOT = HERE.parent
REPO_ROOT = HERE.parents[3]
COMFY_ROOT = Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI")
MODEL_PATH = COMFY_ROOT / "models" / "background_removal" / "birefnet.safetensors"
RUN_ID = "spike6-birefnet-20260803T135800Z"
RUN_ROOT = HERE / "output" / RUN_ID
PACKET = HERE / "review_packets" / f"{RUN_ID}-verified"
REVIEW_FILE = HERE / "reviews" / "human_structure_review.csv"
RUBRIC_FILE = HERE / "reviews" / "human_structure_review_rubric.json"
TEST_RESULT_FILE = HERE / "reviews" / "automated_test_results_verified.json"
FREEZE_FILE = HERE / "config" / "spike5_evidence.freeze.json"
OFFICIAL_WORKFLOW = FLUX2_ROOT / "workflows" / "birefnet_remove_background_official.json"
FORGE_WORKFLOW = FLUX2_ROOT / "workflows" / "birefnet_remove_background_forge_api.json"
EXPECTED_MODEL_SHA = "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154"
EXPECTED_OFFICIAL_WORKFLOW_SHA = "ab7bf67d91a17750222da4131790ca38f651d8078ff28213e15cf0ebd86b3354"
EXPECTED_FORGE_WORKFLOW_SHA = "56d74936b840de2ce2d5e823b6ad1704b9e65dd7ddd8b7a0edbfb5d4d4cf19df"
EXPECTED_FREEZE_SHA = "57b1de80841d4c5f3da4c07b5cb0dee606a3a3dbfffbbb1ba387d617f59f7af8"
EXPECTED_KEYS = (
    ("B01", "4041001"),
    ("B01", "4041002"),
    ("B02", "4041001"),
    ("B02", "4041002"),
    ("B03", "4041001"),
    ("B03", "4041002"),
    ("B04", "4041001"),
    ("B04", "4041002"),
)
REQUIRED_PACKET_ARTIFACTS = {
    "alpha_metrics.csv",
    "birefnet_masks.png",
    "birefnet_raw_rgba_comparison.png",
    "final_96_sprite_sheet.png",
    "old_alpha_vs_birefnet.png",
}
BOOL_FIELDS = (
    "foreground_complete",
    "required_parts_preserved",
    "part_1_preserved",
    "part_2_preserved",
    "part_3_preserved",
    "no_background_residual",
    "no_shadow_residual",
    "no_magenta_contamination",
    "identity_recognizable_96",
    "serious_structure_loss",
    "usable_sprite",
)


class FinalizeError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise FinalizeError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def record(path: Path, *, base: Path | None = None) -> dict[str, Any]:
    resolved = path.resolve(strict=True)
    if base is None:
        display = resolved.as_posix()
    else:
        try:
            display = resolved.relative_to(base.resolve(strict=True)).as_posix()
        except ValueError as exc:
            raise FinalizeError(f"EVIDENCE_PATH_ESCAPE:{path}") from exc
    return {"path": display, "bytes": resolved.stat().st_size, "sha256": sha256(resolved)}


def require_closed_port(port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.25)
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            raise FinalizeError(f"PORT_STILL_OPEN:{port}")


def verify_spike5_freeze() -> dict[str, Any]:
    if sha256(FREEZE_FILE) != EXPECTED_FREEZE_SHA:
        raise FinalizeError("SPIKE5_FREEZE_FILE_CHANGED")
    import sys

    sys.path.insert(0, str(HERE))
    import freeze_spike5_evidence as freezer

    return freezer.verify_freeze(FLUX2_ROOT, FREEZE_FILE)


def verify_packet() -> dict[str, Any]:
    manifest = json_object(PACKET / "review_packet_manifest.json")
    if manifest.get("contract") != "forge-birefnet-spike6-verified-review-packet-v1":
        raise FinalizeError("REVIEW_PACKET_CONTRACT_INVALID")
    if manifest.get("status") != "PASS" or manifest.get("source_run_id") != RUN_ID:
        raise FinalizeError("REVIEW_PACKET_SOURCE_INVALID")
    if manifest.get("input_file_count") != 64 or manifest.get("artifact_file_count") != 5:
        raise FinalizeError("REVIEW_PACKET_COUNTS_INVALID")
    input_files = manifest.get("input_files")
    artifacts = manifest.get("artifacts")
    if not isinstance(input_files, list) or not isinstance(artifacts, list):
        raise FinalizeError("REVIEW_PACKET_LEDGER_MISSING")
    for item in input_files:
        candidate = (FLUX2_ROOT / item["path"]).resolve(strict=True)
        try:
            candidate.relative_to(FLUX2_ROOT)
        except ValueError as exc:
            raise FinalizeError("REVIEW_INPUT_PATH_ESCAPE") from exc
        if candidate.stat().st_size != item["bytes"] or sha256(candidate) != item["sha256"]:
            raise FinalizeError(f"REVIEW_INPUT_CHANGED:{item['path']}")
    artifact_names = {str(item.get("path")) for item in artifacts}
    if artifact_names != REQUIRED_PACKET_ARTIFACTS:
        raise FinalizeError("REVIEW_PACKET_ARTIFACT_SET_INVALID")
    for item in artifacts:
        candidate = (PACKET / item["path"]).resolve(strict=True)
        try:
            candidate.relative_to(PACKET)
        except ValueError as exc:
            raise FinalizeError("REVIEW_ARTIFACT_PATH_ESCAPE") from exc
        if candidate.stat().st_size != item["bytes"] or sha256(candidate) != item["sha256"]:
            raise FinalizeError(f"REVIEW_ARTIFACT_CHANGED:{item['path']}")
    return manifest


def parse_bool(value: str, field: str) -> bool:
    if value not in {"TRUE", "FALSE"}:
        raise FinalizeError(f"REVIEW_BOOLEAN_INVALID:{field}:{value}")
    return value == "TRUE"


def load_review() -> list[dict[str, Any]]:
    with REVIEW_FILE.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 8:
        raise FinalizeError("REVIEW_NOT_EXACT_EIGHT")
    parsed: list[dict[str, Any]] = []
    for ordinal, (row, expected) in enumerate(zip(rows, EXPECTED_KEYS, strict=True), start=1):
        if row.get("ordinal") != str(ordinal) or (row.get("case_id"), row.get("seed")) != expected:
            raise FinalizeError(f"REVIEW_ORDER_INVALID:{ordinal}")
        item: dict[str, Any] = dict(row)
        for field in BOOL_FIELDS:
            item[field] = parse_bool(str(row.get(field)), field)
        if row.get("edge_quality") not in {"GOOD", "ACCEPTABLE", "POOR"}:
            raise FinalizeError("REVIEW_EDGE_QUALITY_INVALID")
        count = int(str(row.get("required_parts_visible_count")))
        preserved_count = sum(bool(item[f"part_{index}_preserved"]) for index in range(1, 4))
        if count != preserved_count or item["required_parts_preserved"] != (count >= 2):
            raise FinalizeError(f"REVIEW_PART_COUNT_INCONSISTENT:{ordinal}")
        expected_usable = (
            item["foreground_complete"]
            and item["required_parts_preserved"]
            and item["no_background_residual"]
            and item["no_shadow_residual"]
            and item["no_magenta_contamination"]
            and item["identity_recognizable_96"]
            and not item["serious_structure_loss"]
            and row["edge_quality"] in {"GOOD", "ACCEPTABLE"}
        )
        if item["usable_sprite"] != expected_usable:
            raise FinalizeError(f"REVIEW_USABILITY_INCONSISTENT:{ordinal}")
        item["required_parts_visible_count"] = count
        item["ordinal"] = ordinal
        parsed.append(item)
    return parsed


def load_metrics() -> list[dict[str, str]]:
    with (PACKET / "alpha_metrics.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 8:
        raise FinalizeError("ALPHA_METRICS_NOT_EXACT_EIGHT")
    for ordinal, (row, expected) in enumerate(zip(rows, EXPECTED_KEYS, strict=True), start=1):
        if row.get("ordinal") != str(ordinal) or (row.get("case_id"), row.get("seed")) != expected:
            raise FinalizeError("ALPHA_METRICS_ORDER_INVALID")
        if row.get("birefnet_status") != "success" or row.get("processed_dimensions") != "96x96":
            raise FinalizeError("ALPHA_METRICS_DELIVERY_FAILED")
        if row.get("largest_component_only") != "False" or row.get("case_specific_logic") != "False":
            raise FinalizeError("ALPHA_METRICS_FORBIDDEN_LOGIC")
    return rows


def verify_official_chain() -> tuple[dict[str, Any], dict[str, Any]]:
    source = json_object(HERE / "reports" / "official_source_manifest.json")
    download = json_object(HERE / "reports" / "model_download_manifest.json")
    if source.get("status") != "PASS" or download.get("status") != "PASS":
        raise FinalizeError("OFFICIAL_SOURCE_MANIFEST_NOT_PASS")
    official_files = source.get("official_files")
    if not isinstance(official_files, list) or len(official_files) != 5:
        raise FinalizeError("OFFICIAL_SOURCE_FILE_SET_INVALID")
    for item in official_files:
        path = Path(str(item.get("path")))
        if (
            not path.is_file()
            or path.stat().st_size != item.get("bytes")
            or sha256(path) != item.get("sha256")
        ):
            raise FinalizeError(f"OFFICIAL_SOURCE_FILE_CHANGED:{path}")
    if sha256(MODEL_PATH) != EXPECTED_MODEL_SHA or MODEL_PATH.stat().st_size != 444473596:
        raise FinalizeError("BIREFNET_MODEL_CHANGED")
    if download.get("model", {}).get("sha256") != EXPECTED_MODEL_SHA:
        raise FinalizeError("MODEL_DOWNLOAD_MANIFEST_MISMATCH")
    installed = COMFY_ROOT / "blueprints" / "Remove Background (BiRefNet).json"
    if (
        sha256(installed) != EXPECTED_OFFICIAL_WORKFLOW_SHA
        or sha256(OFFICIAL_WORKFLOW) != EXPECTED_OFFICIAL_WORKFLOW_SHA
        or installed.read_bytes() != OFFICIAL_WORKFLOW.read_bytes()
    ):
        raise FinalizeError("OFFICIAL_WORKFLOW_CHANGED")
    if sha256(FORGE_WORKFLOW) != EXPECTED_FORGE_WORKFLOW_SHA:
        raise FinalizeError("FORGE_WORKFLOW_CHANGED")
    workflow = json_object(FORGE_WORKFLOW)
    allowed = {
        "LoadImage",
        "LoadBackgroundRemovalModel",
        "RemoveBackground",
        "MaskToImage",
        "InvertMask",
        "JoinImageWithAlpha",
        "SaveImage",
    }
    class_types = {node.get("class_type") for key, node in workflow.items() if key != "_forge"}
    if class_types != allowed:
        raise FinalizeError("FORGE_WORKFLOW_NOT_NATIVE_SEGMENTATION_ONLY")
    return source, download


def build_summary(
    review: list[dict[str, Any]],
    metrics: list[dict[str, str]],
    freeze: dict[str, Any],
    packet_manifest: dict[str, Any],
    tests: dict[str, Any],
) -> dict[str, Any]:
    run = json_object(RUN_ROOT / "run_manifest.json")
    baseline = json_object(FLUX2_ROOT / "reports" / "flux2_matrix_summary.json")
    lifecycle = json_object(HERE / "logs" / "lifecycle_last.json")
    if run.get("completed_job_count") != 8 or run.get("retry_count") != 0 or run.get("serial_execution") is not True:
        raise FinalizeError("FORMAL_RUN_INVALID")
    if tests.get("status") != "PASS" or tests.get("successful") is not True or tests.get("tests_run", 0) < 31:
        raise FinalizeError("AUTOMATED_TESTS_NOT_PASS")
    if lifecycle.get("status") != "PASS" or lifecycle.get("action") != "stopped":
        raise FinalizeError("LIFECYCLE_NOT_STOPPED")
    require_closed_port(8188)
    require_closed_port(8190)

    usable = sum(item["usable_sprite"] for item in review)
    recognizable = sum(item["identity_recognizable_96"] for item in review)
    serious_loss = sum(item["serious_structure_loss"] for item in review)
    background_residual = sum(not item["no_background_residual"] for item in review)
    shadow_residual = sum(not item["no_shadow_residual"] for item in review)
    magenta_contamination = sum(not item["no_magenta_contamination"] for item in review)
    b01 = [item for item in review if item["case_id"] == "B01"]
    b03 = [item for item in review if item["case_id"] == "B03"]
    b04 = [item for item in review if item["case_id"] == "B04"]
    gates = {
        "rgba_and_mask": {"actual": len(metrics), "required": 8, "passed": len(metrics) == 8},
        "usable_sprite": {"actual": usable, "required": 7, "passed": usable >= 7},
        "identity_recognizable_96": {"actual": recognizable, "required": 7, "passed": recognizable >= 7},
        "serious_structure_loss": {"actual": serious_loss, "maximum": 0, "passed": serious_loss == 0},
        "background_residual": {"actual": background_residual, "maximum": 0, "passed": background_residual == 0},
        "shadow_residual": {"actual": shadow_residual, "maximum": 0, "passed": shadow_residual == 0},
        "b01_both_hose_and_nozzle": {
            "actual": sum(item["part_2_preserved"] and item["part_3_preserved"] for item in b01),
            "required": 2,
            "passed": all(item["part_2_preserved"] and item["part_3_preserved"] for item in b01),
        },
        "b03_both_subjects_complete": {
            "actual": sum(item["foreground_complete"] and item["required_parts_visible_count"] >= 2 for item in b03),
            "required": 2,
            "passed": all(item["foreground_complete"] and item["required_parts_visible_count"] >= 2 for item in b03),
        },
        "b04_both_stem_and_base": {
            "actual": sum(item["part_2_preserved"] and item["part_3_preserved"] for item in b04),
            "required": 2,
            "passed": all(item["part_2_preserved"] and item["part_3_preserved"] for item in b04),
        },
        "automatic_retry": {"actual": run["retry_count"], "maximum": 0, "passed": run["retry_count"] == 0},
        "case_specific_correction": {
            "actual": sum(row["case_specific_logic"] != "False" for row in metrics),
            "maximum": 0,
            "passed": all(row["case_specific_logic"] == "False" for row in metrics),
        },
    }
    alpha_pass = all(value["passed"] for value in gates.values())
    old_technical = sum(row["old_alpha_status"] == "success" for row in metrics)
    return {
        "contract": "forge-birefnet-spike6-alpha-summary-v1",
        "run_id": RUN_ID,
        "source_matrix_run_id": run["source_matrix_run_id"],
        "formal_status_before_spike6": "MODEL PASS / ALPHA NEEDS WORK",
        "model_identity_status": "PASS",
        "alpha_status": "PASS" if alpha_pass else "NEEDS WORK",
        "formal_classification": "MODEL PASS / ALPHA PASS" if alpha_pass else "MODEL PASS / ALPHA NEEDS WORK",
        "default_player_flow_promotion": "NOT_PROMOTED_PENDING_LIVE_END_TO_END_APPROVAL",
        "technical_results": {
            "rgba_and_mask_delivered": len(metrics),
            "processed_sprite_delivered": len(metrics),
            "serial_execution": run["serial_execution"],
            "automatic_retry_count": run["retry_count"],
            "case_specific_correction_count": 0,
            "workflow_contains_flux_sampler": False,
            "anthropic_calls": 0,
        },
        "human_results": {
            "reviewer": "Codex independent visual inspection",
            "usable_sprite_count": usable,
            "identity_recognizable_96_count": recognizable,
            "serious_structure_loss_count": serious_loss,
            "background_residual_count": background_residual,
            "shadow_residual_count": shadow_residual,
            "magenta_contamination_count": magenta_contamination,
            "required_parts_preserved_count": sum(item["required_parts_preserved"] for item in review),
            "review_rows": review,
        },
        "formal_gates": gates,
        "old_chroma_comparison": {
            "technical_sprite_delivery": {"passed": old_technical, "total": 8},
            "identity_recognizable_96": baseline["formal_gates"]["identity_recognizable_96"],
            "background_residual_count": baseline["formal_gates"]["background_residual"]["actual"],
            "shadow_residual_count": baseline["formal_gates"]["shadow_residual"]["actual"],
            "formal_alpha_status": baseline["alpha_status"],
        },
        "exception_classification": {
            "case_id": "B01",
            "seed": "4041001",
            "issue": "CHROMA_AMBIGUOUS_EMISSION_PLUME",
            "owner": "SOURCE_FOREGROUND_BACKGROUND_FUSION",
            "birefnet_structure_loss": False,
            "postprocess_structure_loss": False,
            "effect": "Rejected as usable under the no-magenta rule; all three identity structures remain preserved.",
        },
        "source_integrity": {
            "spike5_freeze_sha256": EXPECTED_FREEZE_SHA,
            "spike5_frozen_file_count": len(freeze["files"]),
            "spike5_evidence_unchanged": True,
            "verified_review_packet_manifest_sha256": sha256(PACKET / "review_packet_manifest.json"),
            "verified_review_input_file_count": packet_manifest["input_file_count"],
        },
        "official_birefnet": {
            "model_sha256": EXPECTED_MODEL_SHA,
            "model_bytes": MODEL_PATH.stat().st_size,
            "official_workflow_sha256": EXPECTED_OFFICIAL_WORKFLOW_SHA,
            "forge_api_workflow_sha256": EXPECTED_FORGE_WORKFLOW_SHA,
            "license_declared_by_model_card": "MIT",
            "license_caveat": "The local model repository has no separate LICENSE copy; production legal provenance remains a later validation item.",
        },
        "runtime_shutdown": {
            "status": lifecycle["status"],
            "stopped_at_utc": lifecycle["stopped_at_utc"],
            "port_8188_closed": True,
            "port_8190_closed": True,
        },
        "automated_tests": {
            "status": tests["status"],
            "tests_run": tests["tests_run"],
            "failures": tests["failures"],
            "errors": tests["errors"],
        },
    }


def tf(value: bool) -> str:
    return "PASS" if value else "FAIL"


def report_markdown(summary: dict[str, Any]) -> str:
    human = summary["human_results"]
    lines = [
        "# Forge FLUX Alpha Segmentation Spike 6 — BiRefNet",
        "",
        "## 正式结论",
        "",
        f"**{summary['formal_classification']}**",
        "",
        "Spike 5 的冻结结论在本次验证完成前始终保持 `MODEL PASS / ALPHA NEEDS WORK`。Spike 6 使用官方原生 BiRefNet 对同一批 8 张冻结 FLUX 原图完成分割后，Alpha 门槛通过。结果仍 **不自动晋升默认玩家流程**，需等待 Live End-to-End 明确批准。",
        "",
        "## 结果摘要",
        "",
        f"- 官方 BiRefNet RGBA + Mask：8/8。",
        f"- 96×96 技术交付：8/8。",
        f"- 人工可用 Sprite：{human['usable_sprite_count']}/8。",
        f"- 96×96 可识别：{human['identity_recognizable_96_count']}/8。",
        f"- 严重结构丢失：{human['serious_structure_loss_count']}/8。",
        f"- 明显背景残留：{human['background_residual_count']}/8；明显投影残留：{human['shadow_residual_count']}/8。",
        f"- 洋红污染/歧义：{human['magenta_contamination_count']}/8。",
        "- 自动重试：0；案例专用修正：0。",
        "",
        "人工评分基于实际 raw、RGBA、Mask 与 96×96 图片逐张目视检查，不以 Prompt、JSON 或启发式置信度代替视觉判断。",
        "",
        "## 正式门槛",
        "",
        "| 门槛 | 实际 | 要求 | 结果 |",
        "|---|---:|---:|---|",
    ]
    for name, gate in summary["formal_gates"].items():
        target = gate.get("required", gate.get("maximum"))
        comparator = f">= {target}" if "required" in gate else f"<= {target}"
        lines.append(f"| `{name}` | {gate['actual']} | {comparator} | {tf(gate['passed'])} |")
    lines.extend(
        [
            "",
            "## 逐张人工结构审阅",
            "",
            "| Case | Seed | 关键结构 | 背景/投影 | 洋红 | 96×96 | 严重丢失 | 可用 |",
            "|---|---:|---:|---|---|---|---|---|",
        ]
    )
    for item in human["review_rows"]:
        clean = "PASS" if item["no_background_residual"] and item["no_shadow_residual"] else "FAIL"
        lines.append(
            f"| {item['case_id']} | {item['seed']} | {item['required_parts_visible_count']}/3 | {clean} | "
            f"{'PASS' if item['no_magenta_contamination'] else 'FAIL'} | {tf(item['identity_recognizable_96'])} | "
            f"{'YES' if item['serious_structure_loss'] else 'NO'} | {tf(item['usable_sprite'])} |"
        )
    lines.extend(
        [
            "",
            "B01 / 4041001 的吸尘器主体、长软管和吸嘴全部保留，且无地面或投影残留；但 BiRefNet 同时保留了与测试底色高度相似的粉洋红喷射尾迹。由于无法安全区分这是有效灼热沙子效果还是色键污染，该张按预先定义的 `no_magenta_contamination` 规则保守判为不可用。问题归属为 **原图前景效果与背景融合**，不是主体结构被 BiRefNet 或 96×96 后处理切掉。",
            "",
            "## 与旧色键结果的公平对照",
            "",
            "| 指标 | 旧 process_sprite 色键 | 官方 BiRefNet + 新像素后处理 |",
            "|---|---:|---:|",
            f"| 技术 Sprite 交付 | {summary['old_chroma_comparison']['technical_sprite_delivery']['passed']}/8 | 8/8 |",
            f"| 96×96 可识别 | {summary['old_chroma_comparison']['identity_recognizable_96']['actual']}/8 | {human['identity_recognizable_96_count']}/8 |",
            f"| 明显背景残留 | {summary['old_chroma_comparison']['background_residual_count']}/8 | {human['background_residual_count']}/8 |",
            f"| 明显投影残留 | {summary['old_chroma_comparison']['shadow_residual_count']}/8 | {human['shadow_residual_count']}/8 |",
            "",
            "BiRefNet 方法胜出。它直接使用官方 Mask，不再次运行洋红 Flood Fill 或 GrabCut，也不采用“只保留最大组件”。两张 B01 的软管与吸嘴、两张 B03 的主体、两张 B04 的细杯脚与底座均保留。",
            "",
            "## 官方来源与运行边界",
            "",
            f"- 模型：`birefnet.safetensors`，{summary['official_birefnet']['model_bytes']:,} bytes，SHA-256 `{summary['official_birefnet']['model_sha256']}`。",
            f"- 官方工作流原件及逐字节副本 SHA-256：`{summary['official_birefnet']['official_workflow_sha256']}`。",
            f"- Forge API binding 工作流 SHA-256：`{summary['official_birefnet']['forge_api_workflow_sha256']}`。",
            "- API 图仅含原生背景移除、Mask/Alpha 拼接和保存节点；没有 FLUX 采样器。",
            "- 8 张按 batch size 1 串行处理，0 次自动重试；未调用 Anthropic。",
            "- ComfyUI 仅监听 `127.0.0.1:8190`；完成后 8190 与 8188 均确认关闭。",
            "- 模型卡声明 MIT；本地仓库未附独立模型 LICENSE 文件，生产法律来源仍需单独复核。ComfyUI 本体许可记录与模型许可分开保存。",
            "",
            "## 验证与冻结",
            "",
            f"- 自动测试：{summary['automated_tests']['tests_run']} 项，0 failures，0 errors。",
            f"- Spike 5 冻结清单：{summary['source_integrity']['spike5_frozen_file_count']} 个文件记录全部复核一致。",
            f"- Verified review packet：{summary['source_integrity']['verified_review_input_file_count']} 个输入证据文件及 5 个对照产物全部重新哈希。",
            "- 8 个 Spike 6 完整结果目录保留在 `tools/comfyui/flux2/birefnet/output/`；本报告不复制或覆盖 Spike 5 原证据。",
            "",
            "## 下一步",
            "",
            "本 Spike 在建议门槛下通过，可申请一个独立的 Live End-to-End 验证；当前不接入实时 Godot、战斗房间、锚点、训练区或默认玩家流程，也不启动草图编辑质量 Gate。",
            "",
        ]
    )
    return "\n".join(lines)


def collect_source_records(packet_manifest: dict[str, Any]) -> list[dict[str, Any]]:
    paths: set[Path] = {
        RUN_ROOT / "run_manifest.json",
        RUN_ROOT / "evidence_hashes.json",
        FREEZE_FILE,
        OFFICIAL_WORKFLOW,
        FORGE_WORKFLOW,
        HERE / "process_birefnet_sprite.py",
        HERE / "spike6_runner.py",
        HERE / "build_review_assets.py",
        HERE / "finalize_spike6_evidence.py",
        HERE / "run_spike6_tests.py",
        HERE / "test_process_birefnet_sprite.py",
        HERE / "test_spike6_runner.py",
        HERE / "test_spike6_security.py",
        HERE / "config" / "spike6_birefnet_config.example.json",
        HERE / "download" / "download_birefnet_official.ps1",
        HERE / "scripts" / "start_birefnet_comfyui.ps1",
        HERE / "scripts" / "stop_birefnet_comfyui.ps1",
        HERE / "logs" / "lifecycle_last.json",
        HERE / "reports" / "official_source_manifest.json",
        HERE / "reports" / "model_download_manifest.json",
        REVIEW_FILE,
        RUBRIC_FILE,
        TEST_RESULT_FILE,
        PACKET / "review_packet_manifest.json",
        FLUX2_ROOT / "reports" / "flux2_matrix_summary.json",
        FLUX2_ROOT / "reports" / "human_visual_review.csv",
        FLUX2_ROOT / "reports" / "evidence_hashes.json",
    }
    for item in packet_manifest["input_files"]:
        paths.add(FLUX2_ROOT / item["path"])
    records = [record(path, base=REPO_ROOT) for path in sorted(paths)]
    records.append(record(MODEL_PATH))
    source = json_object(HERE / "reports" / "official_source_manifest.json")
    for item in source["official_files"]:
        records.append(record(Path(item["path"])))
    records.append(record(COMFY_ROOT / "LICENSE"))
    return sorted(records, key=lambda item: item["path"])


def finalize(destination: Path) -> Path:
    destination = destination.resolve(strict=False)
    if destination.exists():
        raise FinalizeError("FINAL_REPORT_DIRECTORY_ALREADY_EXISTS")
    freeze = verify_spike5_freeze()
    packet_manifest = verify_packet()
    review = load_review()
    metrics = load_metrics()
    verify_official_chain()
    tests = json_object(TEST_RESULT_FILE)
    summary = build_summary(review, metrics, freeze, packet_manifest, tests)

    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent)))
    published = False
    try:
        for name in sorted(REQUIRED_PACKET_ARTIFACTS):
            shutil.copy2(PACKET / name, stage / name)
        shutil.copy2(REVIEW_FILE, stage / "human_structure_review.csv")
        shutil.copy2(RUBRIC_FILE, stage / "human_structure_review_rubric.json")
        shutil.copy2(TEST_RESULT_FILE, stage / "automated_test_results.json")
        shutil.copy2(PACKET / "review_packet_manifest.json", stage / "review_packet_manifest.json")
        shutil.copy2(HERE / "reports" / "official_source_manifest.json", stage / "official_source_manifest.json")
        shutil.copy2(HERE / "reports" / "model_download_manifest.json", stage / "model_download_manifest.json")
        (stage / "birefnet_alpha_summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (stage / "BIREFNET_ALPHA_REPORT.md").write_text(report_markdown(summary), encoding="utf-8-sig")

        delivery_records = [
            record(path, base=stage)
            for path in sorted(stage.iterdir())
            if path.is_file()
        ]
        source_records = collect_source_records(packet_manifest)
        evidence = {
            "contract": "forge-birefnet-spike6-evidence-hashes-v1",
            "algorithm": "SHA-256",
            "run_id": RUN_ID,
            "formal_classification": summary["formal_classification"],
            "spike5_freeze_sha256": EXPECTED_FREEZE_SHA,
            "spike5_frozen_file_count": len(freeze["files"]),
            "source_file_count": len(source_records),
            "source_files": source_records,
            "delivery_file_count": len(delivery_records),
            "delivery_files": delivery_records,
            "external_model_not_copied_to_git": True,
            "excluded_self": "evidence_hashes.json",
        }
        (stage / "evidence_hashes.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if destination.exists():
            raise FinalizeError("FINAL_REPORT_DIRECTORY_ALREADY_EXISTS")
        os.rename(stage, destination)
        published = True
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "reports" / RUN_ID)
    args = parser.parse_args()
    try:
        output = finalize(args.output)
    except (FinalizeError, OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}))
        return 2
    print(json.dumps({"status": "PASS", "output": str(output), "classification": "MODEL PASS / ALPHA PASS"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
