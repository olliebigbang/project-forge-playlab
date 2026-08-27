from __future__ import annotations

import ast
import hashlib
import inspect
import json
import re
import subprocess
import sys
import tempfile
import types
import unittest
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlsplit
from unittest import mock

from PIL import Image


TEST_ROOT = Path(__file__).resolve().parent
FLUX2_ROOT = TEST_ROOT.parent
COMFYUI_ROOT = FLUX2_ROOT.parent
PROJECT_ROOT = COMFYUI_ROOT.parents[1]
PROFILE_ROOT = COMFYUI_ROOT / "config" / "profiles"
WORKFLOW_ROOT = FLUX2_ROOT / "workflows"
SCRIPT_ROOT = FLUX2_ROOT / "scripts"
REPORT_ROOT = FLUX2_ROOT / "reports"
RUNTIME_ROOT = Path("C:/AI/ComfyUI-ForgeFlux2")

# The repository test interpreter need not be the isolated ComfyUI interpreter.
# Bridge behavior exercised below replaces ResourceMonitor, so provide only the
# import-time surface when psutil is absent instead of installing or downloading
# anything into the caller's Python environment.
try:
    import psutil as _psutil  # noqa: F401
except ModuleNotFoundError:
    psutil_stub = types.ModuleType("psutil")

    class _PsutilError(Exception):
        pass

    def _unavailable_process(_pid: int) -> object:
        raise _PsutilError("psutil is unavailable in the repository test interpreter")

    psutil_stub.Error = _PsutilError  # type: ignore[attr-defined]
    psutil_stub.Process = _unavailable_process  # type: ignore[attr-defined]
    sys.modules["psutil"] = psutil_stub

for optional_module in ("cv2", "numpy"):
    try:
        __import__(optional_module)
    except ModuleNotFoundError:
        # process_sprite resolves these APIs only when its real processor runs;
        # every bridge delivery test below supplies a deterministic fake
        # processor, so import-only stubs keep this suite dependency-free.
        sys.modules[optional_module] = types.ModuleType(optional_module)

sys.path.insert(0, str(FLUX2_ROOT / "bridge"))
import flux2_profile_bridge as bridge  # noqa: E402


EXPECTED_MODELS = {
    "flux-2-klein-4b-fp8.safetensors": (
        "diffusion_models",
        4_070_624_520,
        "97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6",
    ),
    "qwen_3_4b.safetensors": (
        "text_encoders",
        8_044_982_048,
        "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a",
    ),
    "flux2-vae.safetensors": (
        "vae",
        336_213_556,
        "d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5",
    ),
}

EXPECTED_OFFICIAL_SOURCES = {
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/resolve/main/flux-2-klein-4b-fp8.safetensors",
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors",
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors",
}

T2I_BINDINGS = {
    "positive_prompt",
    "negative_prompt",
    "seed",
    "width",
    "height",
    "steps",
    "guidance",
    "output_subfolder",
}
EDIT_BINDINGS = T2I_BINDINGS | {"optional_reference_image"}

CORE_NODE_TYPES = {
    "UNETLoader",
    "CLIPLoader",
    "VAELoader",
    "CLIPTextEncode",
    "ConditioningZeroOut",
    "EmptyFlux2LatentImage",
    "KSamplerSelect",
    "Flux2Scheduler",
    "RandomNoise",
    "CFGGuider",
    "SamplerCustomAdvanced",
    "VAEDecode",
    "SaveImage",
    "LoadImage",
    "ImageScaleToTotalPixels",
    "VAEEncode",
    "ReferenceLatent",
}


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


@lru_cache(maxsize=None)
def cached_sha256(path_text: str) -> str:
    return sha256_file(Path(path_text))


def model_manifest() -> dict:
    return read_json(REPORT_ROOT / "model_download_manifest.json")


def api_workflow(mode: str) -> dict:
    return read_json(WORKFLOW_ROOT / f"flux2_klein_4b_{mode}_forge_api.json")


def script_text(name: str) -> str:
    path = SCRIPT_ROOT / name
    if not path.is_file():
        raise AssertionError(f"required runtime script missing: {path}")
    return path.read_text(encoding="utf-8")


def binding_paths(binding: object) -> list[list[str]]:
    if isinstance(binding, list) and binding and all(isinstance(item, str) for item in binding):
        return [binding]
    if (
        isinstance(binding, list)
        and binding
        and all(
            isinstance(item, list) and item and all(isinstance(part, str) for part in item)
            for item in binding
        )
    ):
        return binding
    raise AssertionError(f"invalid binding shape: {binding!r}")


def resolve_graph_path(graph: dict, path: list[str]) -> object:
    cursor: object = graph
    for part in path:
        if not isinstance(cursor, dict) or part not in cursor:
            raise AssertionError(f"binding path does not resolve: {'/'.join(path)}")
        cursor = cursor[part]
    return cursor


def executable_flux2_sources() -> list[Path]:
    paths: list[Path] = []
    for root in (FLUX2_ROOT / "bridge", FLUX2_ROOT / "download", FLUX2_ROOT / "scripts"):
        if root.exists():
            paths.extend(path for path in root.rglob("*") if path.suffix.lower() in {".py", ".ps1"})
    paths.append(PROFILE_ROOT / "flux2_klein_4b.json")
    paths.append(PROJECT_ROOT / "scripts" / "services" / "local_comfy_forge_visual_provider.gd")
    return sorted(set(paths))


class RuntimeIsolationAndModelTests(unittest.TestCase):
    """Section 18.1-4: isolated runtime and the exact three-model set."""

    def test_01_runtime_root_is_the_dedicated_c_drive_install(self) -> None:
        profile = read_json(PROFILE_ROOT / "flux2_klein_4b.json")
        self.assertEqual(Path(profile["runtime_root"]), RUNTIME_ROOT)
        self.assertEqual(Path(model_manifest()["runtime_root"]), RUNTIME_ROOT)
        self.assertTrue(RUNTIME_ROOT.is_dir())

    def test_02_runtime_is_not_either_legacy_install(self) -> None:
        profile = read_json(PROFILE_ROOT / "flux2_klein_4b.json")
        runtime = Path(profile["runtime_root"]).resolve()
        legacy = {
            Path("C:/AI/ComfyUI").resolve(),
            Path("C:/Users/Eddie L/Documents/ai漫剧/tools/ComfyUI").resolve(),
        }
        self.assertNotIn(runtime, legacy)
        self.assertEqual(runtime.name, "ComfyUI-ForgeFlux2")

    def test_03_every_runtime_profile_path_stays_in_the_isolated_root(self) -> None:
        profile = read_json(PROFILE_ROOT / "flux2_klein_4b.json")
        for key in ("comfyui_root", "python_executable", "comfy_output_directory", "comfy_input_directory"):
            with self.subTest(key=key):
                path = Path(profile[key]).resolve()
                self.assertTrue(path == RUNTIME_ROOT.resolve() or RUNTIME_ROOT.resolve() in path.parents)

    def test_04_manifest_has_exactly_the_three_approved_models(self) -> None:
        manifest = model_manifest()
        entries = manifest.get("files", [])
        self.assertEqual(len(entries), 3)
        self.assertEqual({entry["filename"] for entry in entries}, set(EXPECTED_MODELS))
        self.assertEqual(manifest.get("contract"), "forge-flux2-model-download-v1")
        self.assertEqual(manifest.get("status"), "PASS")

    def test_05_all_three_model_files_exist_at_the_manifest_destinations(self) -> None:
        for entry in model_manifest()["files"]:
            with self.subTest(filename=entry["filename"]):
                destination = Path(entry["destination"])
                self.assertTrue(destination.is_file(), destination)
                directory, _, _ = EXPECTED_MODELS[entry["filename"]]
                self.assertEqual(destination.parent.name, directory)
                self.assertEqual(destination.parent.parent.parent.parent, RUNTIME_ROOT.resolve())

    def test_06_model_file_lengths_match_manifest_and_frozen_expectations(self) -> None:
        for entry in model_manifest()["files"]:
            with self.subTest(filename=entry["filename"]):
                _, expected_bytes, _ = EXPECTED_MODELS[entry["filename"]]
                actual_bytes = Path(entry["destination"]).stat().st_size
                self.assertEqual(entry["bytes"], expected_bytes)
                self.assertEqual(actual_bytes, expected_bytes)

    def test_07_full_model_sha256_values_match_the_manifest(self) -> None:
        for entry in model_manifest()["files"]:
            with self.subTest(filename=entry["filename"]):
                _, _, expected_hash = EXPECTED_MODELS[entry["filename"]]
                self.assertRegex(entry["sha256"], r"^[0-9a-f]{64}$")
                self.assertEqual(entry["expected_sha256"], expected_hash)
                self.assertEqual(entry["sha256"], expected_hash)
                self.assertEqual(cached_sha256(entry["destination"]), expected_hash)

    def test_08_each_model_has_a_parseable_safetensors_header(self) -> None:
        for entry in model_manifest()["files"]:
            path = Path(entry["destination"])
            with self.subTest(filename=path.name), path.open("rb") as handle:
                header_length = int.from_bytes(handle.read(8), "little")
                self.assertGreaterEqual(header_length, 2)
                self.assertLessEqual(header_length, 100 * 1024 * 1024)
                header = json.loads(handle.read(header_length).decode("utf-8"))
                self.assertIsInstance(header, dict)
                self.assertLess(8 + header_length, path.stat().st_size)

    def test_09_no_unauthorized_weights_or_partial_downloads_exist_in_runtime(self) -> None:
        model_root = RUNTIME_ROOT / "ComfyUI" / "models"
        weights = [path for path in model_root.rglob("*") if path.is_file() and path.suffix.lower() == ".safetensors"]
        # Header/effective-URL sidecars are audit metadata; only an actual
        # weight payload whose final suffix is .partial is incomplete.
        partials = [path for path in model_root.rglob("*") if path.is_file() and path.suffix.lower() == ".partial"]
        self.assertEqual({path.name for path in weights}, set(EXPECTED_MODELS))
        self.assertEqual(partials, [])
        forbidden = re.compile(r"(?i)(?:klein.*(?:base|9b)|flux[-_. ]?2[-_. ]?dev|gguf|lora|controlnet)")
        self.assertFalse(any(forbidden.search(path.name) for path in weights))

    def test_10_model_destinations_are_outside_the_git_worktree(self) -> None:
        project = PROJECT_ROOT.resolve()
        for entry in model_manifest()["files"]:
            destination = Path(entry["destination"]).resolve()
            self.assertNotEqual(destination, project)
            self.assertNotIn(project, destination.parents)


class OfficialWorkflowAndProfileTests(unittest.TestCase):
    """Section 18.5-10: official bytes, API bindings, profiles, and Mock default."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.sources = read_json(REPORT_ROOT / "workflow_sources.json")
        cls.profile = read_json(PROFILE_ROOT / "flux2_klein_4b.json")

    def _source_for_kind(self, kind: str) -> dict:
        return next(item for item in self.sources["templates"] if item["kind"] == kind)

    def test_11_official_t2i_workflow_bytes_match_the_frozen_source_hash(self) -> None:
        record = self._source_for_kind("text_to_image")
        path = PROJECT_ROOT / record["project_path"]
        self.assertEqual(path, WORKFLOW_ROOT / "flux2_klein_4b_t2i_official.json")
        self.assertEqual(sha256_file(path), record["sha256"])
        self.assertEqual(record["sha256"], "f5b2e75448e1ef44ab3d08da00900000f0258f8f963934370c6a1c329d1328c2")

    def test_12_official_edit_workflow_bytes_match_the_frozen_source_hash(self) -> None:
        record = self._source_for_kind("image_edit_distilled")
        path = PROJECT_ROOT / record["project_path"]
        self.assertEqual(path, WORKFLOW_ROOT / "flux2_klein_4b_edit_official.json")
        self.assertEqual(sha256_file(path), record["sha256"])
        self.assertEqual(record["sha256"], "e0388a8870495802314d58fa61616ddcdb7064dac5f85a8787c9e08180b8a560")

    def test_13_api_workflows_bind_back_to_the_exact_official_hashes(self) -> None:
        expected = {
            "t2i": self._source_for_kind("text_to_image")["sha256"],
            "edit": self._source_for_kind("image_edit_distilled")["sha256"],
        }
        for mode, official_hash in expected.items():
            with self.subTest(mode=mode):
                forge = api_workflow(mode)["_forge"]
                self.assertEqual(forge["official_template_sha256"], official_hash)
                self.assertEqual(forge["official_template_commit"], self.sources["commit"])

    def test_14_api_workflows_use_only_the_exact_three_model_filenames(self) -> None:
        for mode in ("t2i", "edit"):
            workflow = api_workflow(mode)
            with self.subTest(mode=mode):
                bridge._assert_workflow_models(workflow)
                serialized = json.dumps(workflow, sort_keys=True)
                for filename in EXPECTED_MODELS:
                    self.assertIn(filename, serialized)
                self.assertNotIn("RealVisXL", serialized)

    def test_15_api_workflows_use_only_declared_comfy_core_node_types(self) -> None:
        for mode in ("t2i", "edit"):
            workflow = api_workflow(mode)
            node_types = {
                node["class_type"]
                for node in workflow.values()
                if isinstance(node, dict) and isinstance(node.get("class_type"), str)
            }
            with self.subTest(mode=mode):
                self.assertTrue(node_types)
                self.assertEqual(node_types - CORE_NODE_TYPES, set())

    def test_16_t2i_forge_binding_set_is_complete(self) -> None:
        workflow = api_workflow("t2i")
        self.assertEqual(set(workflow["_forge"]["bindings"]), T2I_BINDINGS)
        self.assertIn(workflow["_forge"]["output_node_id"], workflow)

    def test_17_edit_forge_binding_set_and_quality_boundary_are_complete(self) -> None:
        workflow = api_workflow("edit")
        forge = workflow["_forge"]
        self.assertEqual(set(forge["bindings"]), EDIT_BINDINGS)
        self.assertFalse(forge["capabilities"]["multi_reference"])
        self.assertFalse(forge["capabilities"]["reference_strength"])
        self.assertFalse(forge["capabilities"]["quality_gate_passed"])
        self.assertNotIn("reference_strength", forge["bindings"])

    def test_18_every_declared_binding_path_resolves_to_an_existing_input(self) -> None:
        for mode in ("t2i", "edit"):
            workflow = api_workflow(mode)
            for name, binding in workflow["_forge"]["bindings"].items():
                for path in binding_paths(binding):
                    with self.subTest(mode=mode, binding=name, path=path):
                        resolve_graph_path(workflow, path)
                        self.assertIn("inputs", path)

    def test_19_profile_injection_writes_every_t2i_parameter(self) -> None:
        workflow = api_workflow("t2i")
        values = {
            "positive_prompt": "positive fixture",
            "negative_prompt": "negative fixture",
            "seed": 4041002,
            "width": 384,
            "height": 640,
            "steps": 7,
            "guidance": 1.25,
            "output_subfolder": "ForgeFlux2/test/output",
        }
        injected, output_id = bridge.inject_profile_workflow(workflow, values)
        self.assertEqual(output_id, "14")
        self.assertNotIn("_forge", injected)
        for name, value in values.items():
            for path in binding_paths(workflow["_forge"]["bindings"][name]):
                with self.subTest(binding=name, path=path):
                    self.assertEqual(resolve_graph_path(injected, path), value)

    def test_20_profile_injection_does_not_mutate_the_template(self) -> None:
        workflow = api_workflow("t2i")
        before = json.dumps(workflow, sort_keys=True)
        bridge.inject_profile_workflow(workflow, {"seed": 99})
        self.assertEqual(json.dumps(workflow, sort_keys=True), before)
        self.assertIn("_forge", workflow)

    def test_21_missing_or_invalid_workflow_bindings_fail_closed(self) -> None:
        workflow = api_workflow("t2i")
        with self.assertRaisesRegex(bridge.Flux2BridgeError, "WORKFLOW_BINDING_MISSING:unknown"):
            bridge.inject_profile_workflow(workflow, {"unknown": 1})
        broken = json.loads(json.dumps(workflow))
        broken["_forge"]["bindings"]["seed"] = ["missing", "inputs", "seed"]
        with self.assertRaisesRegex(bridge.Flux2BridgeError, "WORKFLOW_BINDING_PATH_INVALID"):
            bridge.inject_profile_workflow(broken, {"seed": 1})

    def test_22_flux_profile_has_the_frozen_generation_defaults(self) -> None:
        self.assertEqual(
            self.profile["generation"],
            {
                "width": 512,
                "height": 512,
                "batch_size": 1,
                "steps": 4,
                "guidance": 1.0,
                "sampler": "euler",
                "concurrency": 1,
            },
        )
        self.assertEqual(self.profile["workflow_contract_version"], bridge.WORKFLOW_CONTRACT)

    def test_23_flux_profile_uses_only_127_0_0_1_port_8190(self) -> None:
        self.assertEqual(self.profile["api_base"], "http://127.0.0.1:8190")
        self.assertEqual(bridge.legacy_bridge.validate_api_base(self.profile["api_base"]), self.profile["api_base"])

    def test_24_flux_profile_cannot_resolve_to_a_realvisxl_workflow(self) -> None:
        serialized = json.dumps(self.profile, sort_keys=True).lower()
        self.assertNotIn("realvis", serialized)
        self.assertNotIn("8188", serialized)
        for key in ("t2i_workflow", "edit_workflow"):
            self.assertIn("flux2_klein_4b", self.profile[key])

    def test_25_realvisxl_profile_still_exists_with_its_historical_contract(self) -> None:
        path = PROFILE_ROOT / "realvisxl.json"
        self.assertTrue(path.is_file())
        profile = read_json(path)
        self.assertEqual(profile["profile_id"], "realvisxl")
        self.assertEqual(profile["selected_install_label"], "historical-realvisxl-read-only")
        self.assertEqual(profile["api_base"], "http://127.0.0.1:8188")

    def test_26_bridge_resolves_the_named_flux_profile_and_workflows(self) -> None:
        resolved = bridge.resolve_profile("flux2_klein_4b")
        self.assertEqual(resolved["profile_id"], "flux2_klein_4b")
        self.assertEqual(Path(resolved["t2i_workflow"]), WORKFLOW_ROOT / "flux2_klein_4b_t2i_forge_api.json")
        self.assertEqual(Path(resolved["edit_workflow"]), WORKFLOW_ROOT / "flux2_klein_4b_edit_forge_api.json")
        for mode in ("t2i", "edit"):
            workflow, path, digest = bridge.load_workflow(resolved, mode)
            self.assertEqual(digest, sha256_file(path))
            self.assertEqual(workflow["_forge"]["profile"], "flux2_klein_4b")

    def test_27_playlab_visual_provider_default_remains_mock(self) -> None:
        source = (PROJECT_ROOT / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        self.assertIn("var provider_mode := MODE_MOCK", source)
        self.assertIn('_argument_value("--visual-provider=", MODE_MOCK)', source)
        self.assertRegex(source, r"if provider_mode not in \[MODE_LOCAL_COMFYUI, MODE_MOCK\]:\s*\n\s*provider_mode = MODE_MOCK")

    def test_28_local_provider_has_no_automatic_mock_fallback(self) -> None:
        source = (PROJECT_ROOT / "scripts" / "services" / "local_comfy_forge_visual_provider.gd").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("MockForgeVisualProvider", source)
        self.assertNotIn("MODE_MOCK", source)
        self.assertIn("COMFYUI_TIMEOUT", source)
        self.assertIn("STALE_RESULT_IGNORED", source)

    def test_28b_sketch_edit_requires_the_explicit_developer_switch(self) -> None:
        scene_source = (PROJECT_ROOT / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        provider_source = (
            PROJECT_ROOT / "scripts" / "services" / "local_comfy_forge_visual_provider.gd"
        ).read_text(encoding="utf-8")
        runtime_example = read_json(PROFILE_ROOT / "flux2_klein_4b.runtime.example.json")
        self.assertFalse(runtime_example["enable_sketch_edit"])
        self.assertIn('_has_user_argument("--flux2-enable-sketch-edit")', scene_source)
        self.assertIn("var developer_sketch_edit_enabled := false", provider_source)
        self.assertIn("not profiled_bridge or developer_sketch_edit_enabled", provider_source)


class DownloadScriptSecurityTests(unittest.TestCase):
    """Section 18.4, 18.23 and 18.29: downloader allow-list and atomic delivery."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (FLUX2_ROOT / "download" / "download_flux2_klein_4b.ps1").read_text(encoding="utf-8")
        cls.manifest = model_manifest()

    def test_29_download_origins_are_the_exact_frozen_official_urls(self) -> None:
        origins = {entry["official_source"] for entry in self.manifest["files"]}
        self.assertEqual(origins, EXPECTED_OFFICIAL_SOURCES)
        for origin in EXPECTED_OFFICIAL_SOURCES:
            self.assertIn(origin, self.source)

    def test_30_manifest_urls_use_https_and_only_approved_hosts(self) -> None:
        def allowed(host: str) -> bool:
            host = host.lower()
            return (
                host == "huggingface.co"
                or host.endswith(".huggingface.co")
                or host.endswith(".hf.co")
                or host.endswith(".xethub.hf.co")
            )

        for entry in self.manifest["files"]:
            for field in ("official_source", "resolved_url"):
                parsed = urlsplit(entry[field])
                with self.subTest(filename=entry["filename"], field=field):
                    self.assertEqual(parsed.scheme, "https")
                    self.assertTrue(allowed(parsed.hostname or ""), parsed.hostname)
                    self.assertIsNone(parsed.username)
                    self.assertIsNone(parsed.password)

    def test_31_downloader_requires_40gb_free_on_c_before_download(self) -> None:
        self.assertIn("Get-PSDrive -Name C", self.source)
        self.assertRegex(self.source, r"\$drive\.Free\s+-lt\s+40GB")
        self.assertLess(self.source.index("$drive.Free -lt 40GB"), self.source.index("foreach ($model in $models)"))

    def test_32_downloader_rejects_a_runtime_root_outside_forgeflux2(self) -> None:
        self.assertIn("RUNTIME_ROOT_OUT_OF_SCOPE", self.source)
        self.assertIn("C:\\AI\\ComfyUI-ForgeFlux2", self.source)
        self.assertIn("StartsWith", self.source)

    def test_33_curl_is_fail_fast_resumable_and_has_no_automatic_retry(self) -> None:
        for token in ("'--fail'", "'--location'", "'--continue-at'", "'--retry', '0'"):
            with self.subTest(token=token):
                self.assertIn(token, self.source)
        self.assertIn("$LASTEXITCODE -ne 0", self.source)

    def test_34_download_uses_partial_then_atomic_move(self) -> None:
        partial_index = self.source.index('$partial = "$destination.partial"')
        move_index = self.source.index("[IO.File]::Move($partial, $destination)")
        self.assertLess(partial_index, move_index)
        self.assertIn("if ($candidate -eq $partial)", self.source)
        self.assertNotIn("Copy-Item $partial", self.source)

    def test_35_download_rejects_html_and_validates_nonempty_exact_size(self) -> None:
        self.assertIn("HTML_RESPONSE_REJECTED", self.source)
        self.assertIn("MODEL_SIZE_MISMATCH", self.source)
        self.assertIn("expected_bytes", self.source)
        self.assertIn("SAFETENSORS_TOO_SMALL", self.source)

    def test_36_download_validates_safetensors_header_and_full_sha256(self) -> None:
        self.assertIn("Test-SafetensorsHeader $candidate", self.source)
        self.assertIn("Get-FileHash -LiteralPath $candidate -Algorithm SHA256", self.source)
        self.assertIn("MODEL_SHA256_MISMATCH", self.source)
        for _, _, expected_hash in EXPECTED_MODELS.values():
            self.assertIn(expected_hash, self.source)

    def test_37_download_manifest_captures_http_and_provenance_metadata(self) -> None:
        required = {
            "filename",
            "destination",
            "official_source",
            "resolved_url",
            "bytes",
            "sha256",
            "etag",
            "downloaded_at",
            "license",
            "status",
        }
        for entry in self.manifest["files"]:
            with self.subTest(filename=entry["filename"]):
                self.assertTrue(required <= set(entry))
                self.assertTrue(entry["etag"] or entry.get("last_modified"))
                self.assertIn(entry["status"], {"downloaded_verified", "existing_verified"})

    def test_38_manifest_itself_is_published_atomically(self) -> None:
        self.assertIn('$tempManifest = "$manifestPath.partial"', self.source)
        self.assertIn("[IO.File]::Replace($tempManifest, $manifestPath, $null)", self.source)
        self.assertIn("[IO.File]::Move($tempManifest, $manifestPath)", self.source)

    def test_39_downloader_has_no_token_or_secret_discovery_path(self) -> None:
        lowered = self.source.lower()
        forbidden = (
            "anthropic_api_key",
            "hf_token",
            "huggingface_token",
            "get-childitem env:",
            "credential manager",
            ".netrc",
        )
        for token in forbidden:
            with self.subTest(token=token):
                self.assertNotIn(token, lowered)


class RuntimePowerShellContractTests(unittest.TestCase):
    """Section 18.11-17: lifecycle is verified statically without launching ComfyUI."""

    def test_40_all_four_runtime_scripts_exist(self) -> None:
        expected = {
            "start_flux2_comfyui.ps1",
            "stop_flux2_comfyui.ps1",
            "health_flux2_comfyui.ps1",
            "smoke_flux2_comfyui.ps1",
        }
        self.assertEqual({path.name for path in SCRIPT_ROOT.glob("*.ps1")}, expected)

    def test_41_start_binds_only_127_0_0_1_on_port_8190_and_disables_custom_nodes(self) -> None:
        source = script_text("start_flux2_comfyui.ps1")
        self.assertIn("127.0.0.1", source)
        self.assertIn("8190", source)
        self.assertIn("--listen", source)
        self.assertIn("--port", source)
        self.assertIn("--disable-all-custom-nodes", source)
        for forbidden in ("0.0.0.0", "--listen localhost", "--listen ::"):
            self.assertNotIn(forbidden, source)

    def test_42_start_checks_main_help_before_using_runtime_flags(self) -> None:
        source = script_text("start_flux2_comfyui.ps1")
        lowered = source.lower()
        self.assertIn("main.py", lowered)
        self.assertIn("--help", lowered)
        self.assertLess(lowered.index("--help"), lowered.rindex("--disable-all-custom-nodes"))

    def test_43_start_preflights_manifest_hashes_python_and_cuda(self) -> None:
        source = script_text("start_flux2_comfyui.ps1")
        for token in ("model_download_manifest.json", "Get-FileHash", ".venv"):
            with self.subTest(token=token):
                self.assertIn(token.lower(), source.lower())
        self.assertRegex(source, r"(?i)(nvidia-smi|torch\.cuda\.is_available)")
        self.assertRegex(source, r"(?i)(MODEL_SHA|SHA256).*(MISMATCH|INVALID)|(?:MISMATCH|INVALID).*(MODEL_SHA|SHA256)")

    def test_44_start_refuses_occupied_8190_and_guards_old_8188(self) -> None:
        source = script_text("start_flux2_comfyui.ps1")
        self.assertIn("8190", source)
        self.assertIn("8188", source)
        self.assertRegex(source, r"(?i)(Get-NetTCPConnection|Test-NetConnection|TcpListener|IPGlobalProperties)")
        self.assertRegex(source, r"(?i)8188.*(guard|closed|listen|occupied)|(?:guard|closed|listen|occupied).*8188")

    def test_45_runtime_state_records_owned_pid_and_runtime_identity(self) -> None:
        start = script_text("start_flux2_comfyui.ps1").lower()
        stop = script_text("stop_flux2_comfyui.ps1").lower()
        for token in ("runtime_state", "pid", "comfyui-forgeflux2"):
            with self.subTest(token=token):
                self.assertIn(token, start)
                self.assertIn(token, stop)
        self.assertIn("commandline", start + stop)

    def test_46_health_checks_system_stats_and_exact_profile_endpoint(self) -> None:
        source = script_text("health_flux2_comfyui.ps1")
        self.assertIn("http://127.0.0.1:8190", source)
        self.assertIn("system_stats", source)
        self.assertIn("runtime_state", source.lower())
        self.assertNotIn("http://127.0.0.1:8188", source)

    def test_47_stop_verifies_pid_ownership_before_termination(self) -> None:
        source = script_text("stop_flux2_comfyui.ps1")
        lowered = source.lower()
        self.assertIn("runtime_state", lowered)
        self.assertIn("pid", lowered)
        self.assertRegex(source, r"(?i)(Get-CimInstance|Get-Process)")
        self.assertRegex(source, r"(?i)(commandline|executablepath|runtime_root)")
        self.assertRegex(source, r"(?i)(Stop-Process|\.Kill\()")

    def test_48_stop_waits_for_pid_exit_and_port_8190_release(self) -> None:
        source = script_text("stop_flux2_comfyui.ps1")
        self.assertIn("8190", source)
        self.assertRegex(source, r"(?i)(Wait-Process|HasExited|Get-Process|Get-NetTCPConnection)")
        self.assertRegex(source, r"(?i)(PORT.*8190.*(?:OPEN|LISTEN|CLOSE)|8190.*(?:OPEN|LISTEN|CLOSE))")

    def test_49_no_flux2_script_can_launch_the_old_8188_instance(self) -> None:
        joined = "\n".join(script_text(name) for name in (
            "start_flux2_comfyui.ps1",
            "stop_flux2_comfyui.ps1",
            "health_flux2_comfyui.ps1",
            "smoke_flux2_comfyui.ps1",
        ))
        normalized = re.sub(r"[\s'\",]+", " ", joined.lower())
        self.assertNotIn("--port 8188", normalized)
        self.assertNotIn("http://127.0.0.1:8188", joined.lower())

    def test_50_smoke_uses_the_one_frozen_512px_four_step_request(self) -> None:
        source = script_text("smoke_flux2_comfyui.ps1")
        for token in (
            "one isolated old wooden table",
            "5050001",
            "512",
            "steps",
            "4",
            "batch_size",
            "1",
        ):
            with self.subTest(token=token):
                self.assertIn(token.lower(), source.lower())

    def test_51_oom_low_memory_path_is_explicit_and_limited_to_one_retry(self) -> None:
        source = script_text("smoke_flux2_comfyui.ps1")
        lowered = source.lower()
        self.assertIn("test-cudaoomtext", lowered)
        self.assertTrue("cuda\\s+out\\s+of\\s+memory" in lowered or "cuda out of memory" in lowered)
        self.assertIn("lowmemory", lowered)
        self.assertRegex(lowered, r"(?:attempt|maxattempt|retry).{0,80}(?:2|once|one)|(?:2|once|one).{0,80}(?:attempt|maxattempt|retry)")
        self.assertIn("retry_count", lowered)

    def test_52_runtime_scripts_do_not_read_provider_keys(self) -> None:
        joined = "\n".join(path.read_text(encoding="utf-8") for path in SCRIPT_ROOT.glob("*.ps1")).lower()
        for token in ("anthropic_api_key", "hf_token", "huggingface_token", "openai_api_key"):
            with self.subTest(token=token):
                self.assertNotIn(token, joined)


class OfflineBridgeBehaviorTests(unittest.TestCase):
    """Section 18.15-21: failure, staleness, PNG, raw retention and atomic publication."""

    BLUEPRINT = {
        "identity": {
            "canonical_name_en": "old wooden table",
            "required_identity_parts": ["flat rectangular tabletop", "four wooden legs"],
            "material_hints": ["aged wood"],
            "silhouette_hints": ["side view"],
            "optional_decorations": [],
        },
        "visual": {
            "prompt_en": "one isolated old wooden table",
            "negative_prompt_en": "people, text, extra objects",
            "must_preserve": ["tabletop", "four legs"],
            "must_not_replace_with": ["gun", "sword"],
        },
    }

    class DummyMonitor:
        def __init__(self, _runtime_state: Path) -> None:
            self.peak_vram_mb = 0.0
            self.peak_ram_mb = 0.0

        def __enter__(self) -> "OfflineBridgeBehaviorTests.DummyMonitor":
            return self

        def __exit__(self, *_args: object) -> None:
            return None

    def _offline_profile(self, root: Path) -> dict:
        return {
            "profile_id": "flux2_klein_4b",
            "workflow_contract_version": bridge.WORKFLOW_CONTRACT,
            "t2i_workflow": str(WORKFLOW_ROOT / "flux2_klein_4b_t2i_forge_api.json"),
            "edit_workflow": str(WORKFLOW_ROOT / "flux2_klein_4b_edit_forge_api.json"),
            "model_filenames": dict(bridge.EXPECTED_MODEL_NAMES),
            "model_sha256": {
                "diffusion_model": EXPECTED_MODELS["flux-2-klein-4b-fp8.safetensors"][2],
                "text_encoder": EXPECTED_MODELS["qwen_3_4b.safetensors"][2],
                "vae": EXPECTED_MODELS["flux2-vae.safetensors"][2],
            },
            "selected_install_label": "offline-test",
            "comfyui_commit": "0" * 40,
            "postprocessor": str(COMFYUI_ROOT / "postprocess" / "process_sprite.py"),
            "postprocessor_sha256": "0" * 64,
            "generation": {
                "width": 512,
                "height": 512,
                "batch_size": 1,
                "steps": 4,
                "guidance": 1.0,
                "sampler": "euler",
                "concurrency": 1,
            },
            "timeout_seconds": 1,
            "poll_interval_seconds": 0.0,
            "api_base": "http://127.0.0.1:8190",
            "comfy_output_directory": str(root / "comfy-output"),
            "comfy_input_directory": str(root / "comfy-input"),
            "output_root": str(root / "published"),
            "background_rgb": [255, 0, 255],
            "sprite_size": 96,
            "max_colors": 32,
            "outline": True,
        }

    def _offline_raw_and_entry(self, root: Path, valid: bool = True) -> tuple[Path, dict]:
        raw = root / "comfy-output" / "job" / "result.png"
        raw.parent.mkdir(parents=True)
        if valid:
            Image.new("RGB", (512, 512), (255, 0, 255)).save(raw, format="PNG")
        else:
            raw.write_bytes(b"not a PNG")
        entry = {"outputs": {"14": {"images": [{"subfolder": "job", "filename": "result.png"}]}}}
        return raw, entry

    @staticmethod
    def _successful_postprocessor(_raw: Path, sprite: Path, mask: Path, **_kwargs: object) -> dict:
        Image.new("RGBA", (96, 96), (90, 50, 20, 255)).save(sprite, format="PNG")
        Image.new("L", (96, 96), 255).save(mask, format="PNG")
        return {"processed_dimensions": [96, 96], "alpha_coverage": 1.0, "opaque_bounds": [0, 0, 96, 96]}

    def test_53_api_base_rejects_every_noncanonical_loopback_form(self) -> None:
        self.assertEqual(bridge.legacy_bridge.validate_api_base("http://127.0.0.1:8190/"), "http://127.0.0.1:8190")
        rejected = (
            "http://localhost:8190",
            "http://0.0.0.0:8190",
            "https://127.0.0.1:8190",
            "http://127.0.0.1:8188@evil.example",
            "http://127.0.0.1:8190/path",
            "http://127.0.0.1:8190?next=evil",
        )
        for value in rejected:
            with self.subTest(value=value), self.assertRaises(bridge.legacy_bridge.BridgeError):
                bridge.legacy_bridge.validate_api_base(value)

    def test_54_timeout_cancels_the_prompt_and_fails_explicitly(self) -> None:
        with mock.patch.object(
            bridge.legacy_bridge, "_json_request", return_value={"prompt_id": "job-timeout"}
        ), mock.patch.object(
            bridge.legacy_bridge.time, "monotonic", side_effect=[0.0, 2.0]
        ), mock.patch.object(bridge.legacy_bridge, "_cancel") as cancel:
            with self.assertRaisesRegex(bridge.legacy_bridge.BridgeError, r"COMFYUI_TIMEOUT:1"):
                bridge.legacy_bridge._submit_and_wait(
                    {"api_base": "http://127.0.0.1:8190", "poll_interval_seconds": 0}, {}, 1
                )
        cancel.assert_called_once_with(mock.ANY, "job-timeout")

    def test_55_cuda_oom_history_is_an_explicit_failure_without_resubmission(self) -> None:
        history = {
            "job-oom": {
                "status": {
                    "status_str": "error",
                    "completed": False,
                    "messages": [["execution_error", {"exception_message": "CUDA out of memory"}]],
                }
            }
        }
        responses = [{"prompt_id": "job-oom"}, history]
        with mock.patch.object(bridge.legacy_bridge, "_json_request", side_effect=responses) as request, mock.patch.object(
            bridge.legacy_bridge.time, "monotonic", side_effect=[0.0, 0.1]
        ):
            with self.assertRaisesRegex(
                bridge.legacy_bridge.BridgeError, r"COMFYUI_EXECUTION_FAILED:.*CUDA out of memory"
            ):
                bridge.legacy_bridge._submit_and_wait(
                    {"api_base": "http://127.0.0.1:8190", "poll_interval_seconds": 0}, {}, 5
                )
        self.assertEqual(request.call_count, 2)

    def test_56_formal_generation_contains_one_submit_and_external_retry_evidence(self) -> None:
        source = inspect.getsource(bridge.generate)
        tree = ast.parse(source)
        submit_calls = [
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "_submit_and_wait"
        ]
        self.assertEqual(len(submit_calls), 1)
        self.assertIn('"retry_count": int(visual_retry_count)', source)
        self.assertNotRegex(source, r"(?i)for\s+attempt|while\s+attempt")

    def test_56a_open_identity_prompt_accepts_unicode_without_weakening_explicit_blueprints(self) -> None:
        prompt = "Recognizable original object, player identity text 鱼竿. structural requirement curved shaft."
        open_blueprint = bridge._load_blueprint(None, prompt)
        positive, _negative, evidence = bridge.compose_prompts(open_blueprint)
        self.assertIn("鱼竿", positive)
        self.assertEqual(evidence["input_contract"], "open_identity_generation_prompt_v1")
        self.assertEqual(evidence["generation_prompt_sha256"], hashlib.sha256(prompt.encode("utf-8")).hexdigest())

        explicit_blueprint = json.loads(json.dumps(self.BLUEPRINT))
        explicit_blueprint["visual"]["prompt_en"] = "一张桌子"
        with self.assertRaisesRegex(bridge.Flux2BridgeError, "NON_ASCII_TEXT_REJECTED_FROM_MODEL_HANDOFF"):
            bridge.compose_prompts(explicit_blueprint)

    def test_57_success_is_published_by_one_atomic_directory_replace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = self._offline_profile(root)
            _, entry = self._offline_raw_and_entry(root)
            with mock.patch.object(bridge, "health", return_value={"ok": True}), mock.patch.object(
                bridge, "ResourceMonitor", self.DummyMonitor
            ), mock.patch.object(
                bridge.legacy_bridge, "_submit_and_wait", return_value=("offline-prompt", entry)
            ) as submit, mock.patch.object(
                bridge.legacy_bridge, "process_sprite", side_effect=self._successful_postprocessor
            ), mock.patch.object(bridge.os, "replace", wraps=bridge.os.replace) as atomic_replace:
                final = bridge.generate(
                    profile,
                    case_id="B01",
                    run_id="seed_4041001",
                    output_group="matrix",
                    blueprint=self.BLUEPRINT,
                    seed=4041001,
                )
            self.assertEqual(submit.call_count, 1)
            self.assertEqual(atomic_replace.call_count, 1)
            self.assertTrue((final / "manifest.json").is_file())
            self.assertTrue((final / "raw.png").is_file())
            self.assertTrue((final / "processed_sprite.png").is_file())
            self.assertEqual(list((Path(profile["output_root"]) / ".tmp").glob("*")), [])
            manifest = read_json(final / "manifest.json")
            self.assertEqual(manifest["status"], "success")
            self.assertEqual(manifest["retry_count"], 0)

    def test_57a_mechanism_visual_brief_and_bounded_redraw_count_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = self._offline_profile(root)
            _, entry = self._offline_raw_and_entry(root)
            brief = {
                "schema": "forge-mechanism-visual-brief-v1",
                "source": "ai_mechanism_axes_visual_compiler_v1",
                "automatic": True,
                "player_confirmation_required": False,
                "axes": {"body_continuity": "continuous_flexible"},
                "required_roles": ["grip", "flexible_body", "strike"],
            }
            brief_path = root / "visual-structure-brief.json"
            brief_path.write_text(json.dumps(brief, ensure_ascii=False), encoding="utf-8")
            expected_sha = sha256_file(brief_path)
            with mock.patch.object(bridge, "health", return_value={"ok": True}), mock.patch.object(
                bridge, "ResourceMonitor", self.DummyMonitor
            ), mock.patch.object(
                bridge.legacy_bridge, "_submit_and_wait", return_value=("offline-prompt", entry)
            ) as submit, mock.patch.object(
                bridge.legacy_bridge, "process_sprite", side_effect=self._successful_postprocessor
            ):
                final = bridge.generate(
                    profile,
                    case_id="B01_SOFT",
                    run_id="redraw_2",
                    output_group="matrix",
                    blueprint=self.BLUEPRINT,
                    seed=4041001,
                    prompt_policy_version="forge-open-identity-v3",
                    visual_structure_brief_path=brief_path,
                    visual_retry_count=2,
                )
            self.assertEqual(submit.call_count, 1)
            self.assertEqual(read_json(final / "visual_structure_brief.json"), brief)
            manifest = read_json(final / "manifest.json")
            self.assertEqual(manifest["prompt_policy_version"], "forge-open-identity-v3")
            self.assertEqual(manifest["retry_count"], 2)
            self.assertEqual(manifest["visual_structure_brief_sha256"], expected_sha)
            self.assertEqual(manifest["mechanism_visual_gate"], "pending_godot_alpha_and_rig_evaluation")

    def test_57b_visual_redraw_count_is_bounded_without_bridge_resubmission(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            profile = self._offline_profile(Path(directory))
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "VISUAL_RETRY_COUNT_INVALID"):
                bridge.generate(
                    profile,
                    case_id="B01",
                    run_id="redraw_3",
                    output_group="matrix",
                    blueprint=self.BLUEPRINT,
                    seed=4041001,
                    visual_retry_count=3,
                )

    def test_58_alpha_failure_retains_raw_and_never_publishes_a_fake_sprite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = self._offline_profile(root)
            _, entry = self._offline_raw_and_entry(root)
            with mock.patch.object(bridge, "health", return_value={"ok": True}), mock.patch.object(
                bridge, "ResourceMonitor", self.DummyMonitor
            ), mock.patch.object(
                bridge.legacy_bridge, "_submit_and_wait", return_value=("offline-prompt", entry)
            ), mock.patch.object(
                bridge.legacy_bridge,
                "process_sprite",
                side_effect=bridge.legacy_bridge.SpritePostprocessError("OBJECT_TOUCHES_RAW_EDGE"),
            ):
                final = bridge.generate(
                    profile,
                    case_id="B02",
                    run_id="seed_4041001",
                    output_group="matrix",
                    blueprint=self.BLUEPRINT,
                    seed=4041001,
                )
            manifest = read_json(final / "manifest.json")
            self.assertEqual(manifest["status"], "raw_success_alpha_failed")
            self.assertEqual(manifest["failure_reason"], "OBJECT_TOUCHES_RAW_EDGE")
            self.assertTrue((final / "raw.png").is_file())
            self.assertFalse((final / "processed_sprite.png").exists())
            self.assertFalse((final / "alpha_mask.png").exists())

    def test_59_corrupt_and_wrong_format_images_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            corrupt = root / "corrupt.png"
            corrupt.write_bytes(b"not a PNG")
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "RAW_PNG_INVALID"):
                bridge._validate_raw_png(corrupt, (512, 512))
            jpeg = root / "actually.jpeg"
            Image.new("RGB", (512, 512), "white").save(jpeg, format="JPEG")
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "RAW_NOT_PNG"):
                bridge._validate_raw_png(jpeg, (512, 512))

    def test_60_wrong_png_dimensions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "small.png"
            Image.new("RGB", (96, 96), "white").save(path, format="PNG")
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "RAW_DIMENSIONS_INVALID"):
                bridge._validate_raw_png(path, (512, 512))

    def test_61_output_path_traversal_and_multiple_outputs_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output_root = root / "output"
            output_root.mkdir()
            escaped = root / "escaped.png"
            Image.new("RGB", (512, 512), "white").save(escaped)
            profile = {"comfy_output_directory": str(output_root)}
            traversal = {"outputs": {"14": {"images": [{"subfolder": "..", "filename": "escaped.png"}]}}}
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "COMFYUI_OUTPUT_FILE_INVALID"):
                bridge._extract_output(profile, traversal, "14")
            multiple = {"outputs": {"14": {"images": [{}, {}]}}}
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "EXPECTED_ONE_OUTPUT_IMAGE:2"):
                bridge._extract_output(profile, multiple, "14")

    def test_62_existing_final_directory_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = self._offline_profile(root)
            final = root / "published" / "matrix" / "b01" / "seed_4041001"
            final.mkdir(parents=True)
            sentinel = final / "sentinel.txt"
            sentinel.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(bridge.Flux2BridgeError, "FINAL_DIRECTORY_ALREADY_EXISTS"):
                bridge.generate(
                    profile,
                    case_id="B01",
                    run_id="seed_4041001",
                    output_group="matrix",
                    blueprint=self.BLUEPRINT,
                    seed=4041001,
                )
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_63_godot_provider_checks_revision_before_reading_atomic_result(self) -> None:
        source = (PROJECT_ROOT / "scripts" / "services" / "local_comfy_forge_visual_provider.gd").read_text(
            encoding="utf-8"
        )
        function = source[source.index("func _load_completed_result"): source.index("func _failure")]
        self.assertIn("if not accepts_revision(active_revision)", function)
        self.assertIn("STALE_RESULT_IGNORED", function)
        self.assertLess(function.index("accepts_revision"), function.index("JSON.parse_string"))


class RepositoryBoundaryAndSecretTests(unittest.TestCase):
    """Section 18.22-30: Web/Git/scope/no-provider/no-Gate-A/no-V2/secret boundaries."""

    def test_64_web_export_excludes_all_comfyui_assets_and_models(self) -> None:
        export = (PROJECT_ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        self.assertRegex(export, r'exclude_filter="[^"]*tools/comfyui/\*')
        build = PROJECT_ROOT / "build" / "web"
        if build.exists():
            forbidden = [
                path
                for path in build.rglob("*")
                if path.is_file() and (path.suffix.lower() in {".safetensors", ".partial"} or path.name in EXPECTED_MODELS)
            ]
            self.assertEqual(forbidden, [])

    def test_65_gitignore_blocks_flux_outputs_local_config_weights_and_partials(self) -> None:
        ignore = (PROJECT_ROOT / ".gitignore").read_text(encoding="utf-8")
        required = (
            "tools/comfyui/flux2/output/",
            "tools/comfyui/flux2/.tmp/",
            "tools/comfyui/flux2/logs/",
            "tools/comfyui/flux2/config/*.local.json",
            "*.safetensors",
            "*.partial",
        )
        for rule in required:
            with self.subTest(rule=rule):
                self.assertIn(rule, ignore)

    def test_66_git_tracks_no_model_partial_or_flux_output_file(self) -> None:
        result = subprocess.run(
            ["git", "ls-files", "-z"], cwd=PROJECT_ROOT, capture_output=True, check=True
        )
        tracked = [item.decode("utf-8", errors="surrogateescape").replace("\\", "/") for item in result.stdout.split(b"\0") if item]
        forbidden = [
            path
            for path in tracked
            if path.lower().endswith((".safetensors", ".partial"))
            or path.lower().startswith("tools/comfyui/flux2/output/")
        ]
        self.assertEqual(forbidden, [])

    def test_67_worktree_identity_is_the_standalone_playlab_repository(self) -> None:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=PROJECT_ROOT, text=True, capture_output=True, check=True
        )
        worktree = Path(result.stdout.strip()).resolve()
        self.assertEqual(worktree, PROJECT_ROOT.resolve())
        self.assertEqual(worktree.name, "project-forge-playlab")
        self.assertNotEqual(worktree.name, "project forge")
        self.assertNotEqual(worktree.name, "project-forge-claude")

    def test_68_flux2_project_files_do_not_escape_through_links_to_other_repositories(self) -> None:
        root = PROJECT_ROOT.resolve()
        for path in FLUX2_ROOT.rglob("*"):
            if not path.is_file():
                continue
            with self.subTest(path=path):
                resolved = path.resolve()
                self.assertIn(root, resolved.parents)
                self.assertFalse(path.is_symlink())

    def test_69_no_gameplay_room_file_is_modified_for_flux2_integration(self) -> None:
        result = subprocess.run(
            ["git", "status", "--porcelain=v1", "--untracked-files=all"],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=True,
        )
        changed = result.stdout.replace("\\", "/").lower()
        forbidden_paths = (
            "scenes/room1",
            "scenes/room_1",
            "scenes/room2",
            "scenes/room_2",
            "scripts/rooms/",
            "scripts/systems/room1",
            "scripts/systems/room2",
        )
        for forbidden in forbidden_paths:
            with self.subTest(path=forbidden):
                self.assertNotIn(forbidden, changed)

    def test_70_flux2_integration_has_no_combat_room_or_level_transition(self) -> None:
        sources = "\n".join(path.read_text(encoding="utf-8") for path in executable_flux2_sources()).lower()
        for token in ("room_1", "room_2", "room1.tscn", "room2.tscn", "change_scene_to", "change_scene_to_file"):
            with self.subTest(token=token):
                self.assertNotIn(token, sources)

    def test_71_flux2_executables_never_call_anthropic(self) -> None:
        for path in executable_flux2_sources():
            source = path.read_text(encoding="utf-8").lower()
            with self.subTest(path=path):
                self.assertNotIn("anthropic", source)
                self.assertNotIn("api.anthropic.com", source)
                self.assertNotIn("claude", source)

    def test_72_flux2_executables_do_not_execute_gate_a(self) -> None:
        for path in executable_flux2_sources():
            source = path.read_text(encoding="utf-8").lower()
            with self.subTest(path=path):
                self.assertNotRegex(source, r"gate[_ -]?a(?:_runner|\\|/|\.py|\.ps1)")
                self.assertNotIn("run_gate_a", source)

    def test_73_flux2_executables_do_not_start_v2(self) -> None:
        for path in executable_flux2_sources():
            source = path.read_text(encoding="utf-8").lower()
            with self.subTest(path=path):
                self.assertNotRegex(source, r"(?:--|start[_ -]|launch[_ -]|run[_ -])v2\b")
                self.assertNotIn("project-forge-v2", source)

    def test_74_secret_scan_finds_no_high_confidence_key_material(self) -> None:
        patterns = {
            "anthropic_key": re.compile(r"sk-ant-[A-Za-z0-9_-]{16,}"),
            "openai_key": re.compile(r"sk-(?:proj-)?[A-Za-z0-9_-]{24,}"),
            "huggingface_token": re.compile(r"hf_[A-Za-z0-9]{20,}"),
            "aws_access_key": re.compile(r"AKIA[0-9A-Z]{16}"),
            "private_key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        }
        candidates = [
            path
            for path in FLUX2_ROOT.rglob("*")
            if path.is_file()
            and TEST_ROOT not in path.parents
            and path.suffix.lower() in {".py", ".ps1", ".json", ".md", ".txt", ".csv"}
        ]
        findings: list[str] = []
        for path in candidates:
            source = path.read_text(encoding="utf-8", errors="replace")
            for label, pattern in patterns.items():
                if pattern.search(source):
                    findings.append(f"{label}:{path.relative_to(PROJECT_ROOT)}")
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
