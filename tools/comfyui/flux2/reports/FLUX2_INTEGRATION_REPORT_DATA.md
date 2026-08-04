# FLUX.2 Spike 5 Evidence Summary

> This is a mechanically generated evidence summary. It is not the final integration report.

- Matrix run: `flux2-matrix-20260803T130451548924Z`
- Human review: **COMPLETE**
- Formal classification: **MODEL PASS / ALPHA NEEDS WORK**
- Raw generation: 8/8
- Current v1 Alpha delivery: 6/8
- Automatic retries: 0
- Frozen RealVisXL 4A evidence unchanged: true

## Per-image technical evidence

| Case | Seed | Generation | Alpha | Failure | Gen s | Post s | Peak VRAM MB |
|---|---:|---|---|---|---:|---:|---:|
| B01 | 4041001 | raw delivered | delivered | - | 2.527 | 0.088 | 11481.0 |
| B01 | 4041002 | raw delivered | delivered | - | 1.033 | 0.042 | 11399.0 |
| B02 | 4041001 | raw delivered | delivered | - | 2.177 | 0.05 | 11570.0 |
| B02 | 4041002 | raw delivered | delivered | - | 1.04 | 0.043 | 11449.0 |
| B03 | 4041001 | raw delivered | rejected | OBJECT_TOUCHES_RAW_EDGE | 2.032 | 0.027 | 11577.0 |
| B03 | 4041002 | raw delivered | rejected | OBJECT_TOUCHES_RAW_EDGE | 1.02 | 0.017 | 11497.0 |
| B04 | 4041001 | raw delivered | delivered | - | 2.036 | 0.047 | 11641.0 |
| B04 | 4041002 | raw delivered | delivered | - | 1.007 | 0.039 | 11481.0 |

## Performance

- Mean generation: 1.609 s
- Maximum generation: 2.527 s
- Total matrix wall time: 13.401 s
- Maximum observed VRAM: 11641.0 MB
- Maximum observed RAM: 14189.6 MB

## Review boundary

Human fields were loaded from the independent review CSV and were not inferred from prompts.
The final report must keep raw model identity and Alpha delivery as separate conclusions.
