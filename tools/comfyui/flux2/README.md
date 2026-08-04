# Forge FLUX.2 Klein 4B Spike 5

This directory contains only the Playlab-side configuration, official workflow
snapshots, API adaptations, bridge profile support, tests, and evidence for the
isolated FLUX.2 Klein 4B Distilled FP8 experiment.

The runtime and model weights live outside Git at:

`C:\AI\ComfyUI-ForgeFlux2`

The two historical ComfyUI installations and all RealVisXL evidence are read-only
inputs to this Spike. The Playlab default visual provider remains `MOCK`.

Approved generation defaults are 512x512, batch 1, 4 steps, CFG 1.0, explicit
seed, and concurrency 1. ComfyUI listens only on `127.0.0.1:8190` while a run is
active. Image edit is wired behind the developer-only
`--flux2-enable-sketch-edit` switch and is not a passed quality gate.

Run commands and final status are recorded in
`reports/FLUX2_INTEGRATION_REPORT.md`.
