<!-- graphify-gdscript:start -->
## graphify-gdscript

This Godot project has a graphify-gdscript knowledge graph at graphify-out/ covering .gd scripts, .tscn scenes, project.godot autoloads, .tres resources, signals and node paths.

When the user types `/graphify-gdscript` (or `$graphify-gdscript` in Codex), use the installed graphify-gdscript skill before doing anything else.

Rules:
- When graphify-out/graph.json exists, run `graphify-gdscript query "<question>"` before your first grep, search or raw read of .gd, .tscn, .tres or project.godot files, and put this rule in every subagent prompt that explores the project. Use `graphify-gdscript trace "<signal>"` for signal flow, `graphify-gdscript path "<A>" "<B>"` for relationships and `graphify-gdscript explain "<symbol>"` for one symbol. Read raw files only for lines the graph already located.
- Signals are often connected in .tscn files rather than code: run `trace` before deciding a signal is unused.
- Read graphify-out/GRAPH_REPORT.md only for a broad architecture review.
- After modifying project files, run `graphify-gdscript scan` to keep the graph current (AST-only, no API cost).
<!-- graphify-gdscript:end -->

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify-gdscript scan` (NOT `graphify update .` — upstream graphify cannot parse .gd/.tscn yet and would overwrite the Godot graph with a docs-only one).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
