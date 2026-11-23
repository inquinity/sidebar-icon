# Contract: Glyph builder (SVG → symbol template → Assets.car)

Research D4, D5; spike S2, S2b, S7.

## SVGShapeReader

Input: the owner's SVG file (UTF-8, ≤ 1 MB).

| Accepted | Converted to path data |
|----------|------------------------|
| `<svg viewBox="x y w h">` (required; `width`/`height` ignored) | — |
| `<path d fill-rule>` with `fill` not `none` | as is |
| `<rect x y width height rx ry>` | path with arcs |
| `<circle cx cy r>`, `<ellipse cx cy rx ry>` | two arcs |
| `<polygon points>` | `M … L … Z` |
| `<g>` without `transform`; `<title>`, `<desc>`, `<defs>` (empty), comments | ignored containers |

| Refused (`unsupportedSVG`) | Guidance shown |
|----------------------------|----------------|
| any element with `stroke` other than `none` and `fill="none"`; `<line>`, `<polyline>` | "Convert strokes to shapes: Outline Stroke / Stroke to Path in your drawing app" |
| `<text>` | "Convert text to outlines" |
| `<image>`, `<use>`, `<pattern>`, gradients, `<mask>`, `<clipPath>`, `<filter>` | "Flatten to plain filled shapes" |
| `transform` on any element | "Export with transforms flattened" |
| no shapes | `emptySVG` |

Output: `[(d: String, fillRule: String)]`, the `viewBox`, width ratio (w / h), and a detail
estimate (path command count) for preview warnings (width ratio outside 0.8–1.25, or very many
commands).

## SymbolTemplateWriter

- Canvas `0 0 3300 2200`; guides `Baseline-S/M/L`, `Capline-S/M/L` (cap height 70.459).
- Glyphs `Ultralight-M`, `Regular-M`, `Black-M` (same geometry), each with left and right margin
  lines; the art scaled uniformly so its `viewBox` height maps to **150 units**, from 120 above the
  baseline to 30 below; horizontally from the weight's left margin.
- Deterministic output (same input, same bytes).

## AssetCatalogWriter + ActoolRunner

- Writes `Build/<build id>/Glyphs.xcassets` with one `<name>.<versionID>.symbolset` per glyph
  (`Contents.json` with `"template-rendering-intent": "template"`).
- Runs `actool` (research D5) into `Build/<build id>/out/`; success = exit 0, no `errors` in the
  XML output, and `Assets.car` present. Then deletes `Build/<build id>`, except the car, which
  moves into the new registry bundle.
- `ToolStatus`:
  - `available(path)`: `xcrun --find actool` printed a path inside a `Developer/` directory and
    the file is executable;
  - otherwise `unavailable(reason)`, with the reason in plain language.

## Errors → messages

| Condition | Message |
|-----------|---------|
| `xcrun` reports no developer directory, or only Command Line Tools | "Custom glyphs need Xcode (the Command Line Tools don't include the asset tool). Install Xcode, or use a system glyph." |
| license not accepted | "Open Xcode once and accept its license, then try again." |
| first-launch components missing | "Open Xcode once to finish installing its components, then try again." |
| other `actool` error | "The asset tool couldn't build the glyph: <first error line>." |
| timeout (120 s) | "The asset tool didn't finish in time; nothing was changed." |
