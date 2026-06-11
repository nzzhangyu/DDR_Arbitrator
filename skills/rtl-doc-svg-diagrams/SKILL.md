---
name: rtl-doc-svg-diagrams
description: Use when documenting RTL modules, frame formats, signal muxes, protocol timing, or architecture notes in Markdown, especially when the user wants precise SVG diagrams with aligned blocks, boundary conditions, and hardware-style signal annotations.
---

# RTL Doc SVG Diagrams

Use this skill when explaining or updating RTL documentation for modules, frame structures, signal selection logic, or protocol timing.

Prefer repository-local Markdown plus SVG diagrams. Use exact module, signal, and file names from the code.

## Document Intake Workflow

When first explaining or documenting a new RTL file, module group, or architecture document, start with structure before details.

Required first-pass order:

1. Code hierarchy
2. SVG hierarchy diagram
3. Overall logic/function description
4. Short submodule or sub-block descriptions
5. Frame structure or signal-level details
6. Timing, counters, CDC, and edge cases

When writing a full module Markdown document, make the module function chapter follow the same code hierarchy order and numbering as the hierarchy diagram. Do not split the function chapter into separate "top module" and "submodule" sections if that breaks code hierarchy order.

### Code Hierarchy

- Identify the top module, direct child modules, major always blocks, functions, FIFOs, CRC units, CDC paths, and external interfaces.
- Present the hierarchy in text before detailed explanation.
- Keep hierarchy focused on the relevant module group.
- Do not expand unrelated project areas.

Example shape:

```text
top_module
├── control FSM
├── data path mux
├── header generator
├── payload generator
├── CRC lane 0..3
└── output interface
```

### SVG Hierarchy Diagram

- Create or update an SVG hierarchy diagram under the document's existing `images/` directory.
- Use SVG, not Mermaid.
- Prefer a vertical tree expansion layout for code/module hierarchy diagrams, like a source tree or outline.
- Place the top module at the top-left, then expand children downward with indentation.
- Use elbow connectors, vertical guide lines, or tree branches to show parent-child ownership.
- Do not draw hierarchy as a freeform node graph with curved links or widely spread boxes.
- Do not rely on left-to-right reading for hierarchy; the main reading direction should be top-to-bottom.
- Keep all nodes in a readable single-column or lightly indented multi-column tree, with consistent indentation per level.
- Keep labels short.
- Use dark text.
- Avoid decorative icons.
- Avoid overview diagrams where boxes float across the canvas and relationships are shown mostly by long diagonal or curved arrows.
- Show the top module, main internal logic blocks, important child module instances, and main data/control direction where useful.
- If a module has no child instances, show logical blocks such as counters, muxes, FSMs, lookup tables, CRC lanes, and output registers.

Suggested shape:

```text
top module
├── major child module A
│   ├── submodule / logic block
│   └── FIFO / CDC block
├── major child module B
│   ├── FSM
│   └── mux / output block
└── major child module C
```

## Overall Logic Description

After the hierarchy, add a concise overall description:

- What the module is responsible for.
- What it receives.
- What it generates.
- Which module owns the surrounding protocol/state machine.
- What clock/reset domain it runs in.
- What it deliberately does not do.

Keep this to one paragraph unless the module is large.

## Module Function Chapter Numbering

For repository module documentation, use a dedicated module function chapter after the code hierarchy chapter.

Preferred chapter shape:

```text
## 1. Overall function
## 2. Code hierarchy
## 3. Module function introduction
### 3.1 top_module
### 3.2 first direct child in code hierarchy
### 3.3 second direct child in code hierarchy
#### 3.3.1 child instance under 3.3
#### 3.3.2 next child instance under 3.3
### 3.4 next direct child
## 4. Data flow
## 5. Frame/output structure
## 6. Clock domains
```

Rules:

- The function chapter must be ordered by the actual code hierarchy and instance order.
- Number child instances under their parent module, not as unrelated top-level sections.
- If a module has generated variants such as `_32`, document them in the same section as the base module.
- If an important instantiated module was missing from previous docs, add it to the hierarchy diagram, hierarchy table, and function chapter.
- Keep frame-structure details under the module that generates or owns that frame data.
- In the top-level document order, place code frame-structure chapters after the main data-flow chapter so readers understand the path before the packet/frame layout.
- If later chapters are renumbered by inserting or merging sections, update all subsequent chapter numbers consistently.

## Short Submodule Descriptions

Add a compact list for each child module or major logic block.

For each item include:

- Name
- Role
- Main inputs
- Main outputs
- Important timing or enable condition

Example:

```markdown
- `CRC_16_header_data` lane 0..3: calculates one 16-bit CRC lane each; driven by `crc_en/clear_crc`; outputs are packed into `crc_out`.
- Header word map: maps `header_cnt` to four 16-bit header words; includes `DMS_Type`, `L_FTP_temp`, and `R_FTP_temp`.
- Output mux: selects command, payload, footer, or CRC data into `idle_data_out` according to frame-stage enables.
```

## Diagram Style

- Use standalone SVG files under the document's existing `images/` directory.
- Reference SVGs from Markdown with normal image syntax.
- Use SVG for RTL frame structures and selection logic; avoid Mermaid, HTML tables, icons, and generic flowcharts for these cases.
- Draw frame structures as adjacent rectangular blocks.
- Align corresponding blocks across rows with identical `x` and `width` values.
- Do not use arrows between frame blocks when the relationship is sequential adjacency.
- Use arrows only when pointing to a transition condition, boundary, or selection point.
- Put transition or selection conditions at block boundaries, not centered over a block.
- Use a short arrow from the condition text to the exact boundary it describes.
- Avoid decorative symbols and visual clutter.

## Text Style

- Do not use pale or low-contrast text.
- Use dark text such as `#0f172a`.
- Differentiate hierarchy with font size and weight, not light colors.
- Suggested hierarchy:
  - Title: large and bold.
  - Block names: medium and bold.
  - Conditions: smaller, bold, monospace.
  - Signal/data values: monospace, dark, medium weight.
  - Notes: small but still dark and readable.

## Frame Structure Diagrams

For frame formats, show each logical frame as one row.

Example row shape:

```text
frame name | SOF | command | payload | footer | CRC | EOF
```

Rules:

- SOF/EOF blocks should appear as real blocks if they are part of the frame sequence.
- If SOF/EOF are generated by another module, note that in the diagram or nearby text.
- Command, payload, footer, and CRC blocks should show the data source or signal value.
- If two frame types share the same shape, put them in one SVG with aligned rows.
- Do not title a section "merged structure"; use the natural domain name, such as `idle frame structure`.

## Signal Selection Diagrams

For mux or `always_comb` selection logic, draw the possible outputs as adjacent blocks in priority order.

Rules:

- Use one block per selected output.
- Put the condition at the entry boundary of that block.
- Add a short arrow from condition text to that boundary.
- The first condition points to the left edge of the first block.
- Later conditions point to the boundary between the previous block and the current block.
- The block interior shows the value assigned to the output.
- Use `default` as the final fallback condition when the code has an `else` path.

Example shape:

```text
crc_out | H_FRAME_HEADER_DATA | s_frame_header_data | header_data | FOOTER_DATA | idle_data_out_t
```

Boundary labels:

```text
crc_tx_2_en
header_cmd_2_en
slice_cmd_2_en
header_en
footer_en
default
```

## Markdown Integration

- Keep the Markdown explanation concise.
- Put detailed visual structure in SVG, not in repeated tables.
- After an SVG, add only the minimum text needed to clarify ownership.
- Remove redundant tables if the SVG already carries the same information.

Useful clarification examples:

- SOF/EOF are generated by the frame controller.
- Payload data is provided by the generator module.
- Conditions shown on boundaries correspond to RTL control signals.

## RTL Documentation Tone

- Explain signals by their role in the hardware path.
- Prefer module-local wording: what this module generates, what another module controls.
- Avoid vague terms like "icon", "flow", or "beautiful diagram" when the request is about RTL.
- Use exact signal names from the code.
