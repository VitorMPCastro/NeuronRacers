# Neuron Racers — Minimal Developer README

Notion Link
[https://neuron-racers.notion.site/Neuron-Racers](https://neuron-racers.notion.site/Neuron-Racers-27a2613bc979809d8f62f62966b453a4)

Short overview
- Neuron Racers is a Godot 4 project that simulates vehicle agents trained by neural networks and exposes UI tooling (HUD, leaderboard, and a reusable node editor for constructing fitness expressions).
- Core systems: AgentManager (evolution + spawn), GameManager (scene glue), DataBroker (typed data access for UI and node graph), NodeGraph (visual node editor for fitness/formulas).

Quick start
1. Open the Godot project at the folder containing this README.
2. Run the main scene (e.g., `scenes/trackScene.tscn`).
3. The HUD is created by: [`scripts/ui/hud_setup.gd`](scripts/ui/hud_setup.gd). Add a Node Editor toggle to the bottom bar via the `NodeEditorToggle` scene:
   - Toggle scene: [`scenes/ui/node_editor_toggle.tscn`](scenes/ui/node_editor_toggle.tscn)
   - Toggle script: [`scripts/ui/nodegraph/node_editor_toggle.gd`](scripts/ui/nodegraph/node_editor_toggle.gd)
4. Node Editor popup: [`scenes/ui/node_editor_popup.tscn`](scenes/ui/node_editor_popup.tscn) with controller [`scripts/ui/nodegraph/node_editor_popup.gd`](scripts/ui/nodegraph/node_editor_popup.gd).

Architecture — key components
- Agent/Evolution
  - [`scripts/manager/agentManager.gd`](scripts/manager/agentManager.gd) — population, spawn, fitness evaluation hooks, MLP persistence.
  - MLP resource: [`scripts/ai/MLP.gd`](scripts/ai/MLP.gd)
- Data and telemetry
  - [`scripts/telemetry/dataBroker.gd`](scripts/telemetry/dataBroker.gd) — single API to query object properties and helper tokens used by UI and node graph.
- HUD & UI
  - UI frame: [`scenes/ui/UIFrame.tscn`](scenes/ui/UIFrame.tscn) and controller [`scripts/ui/uiFrame.gd`](scripts/ui/uiFrame.gd).
  - HUD builder: [`scripts/ui/hud_setup.gd`](scripts/ui/hud_setup.gd) — adds Leaderboard, Top/Bottom bars and the Node Editor toggle.
  - Leaderboard: [`scenes/ui/elements/leaderboard_container.tscn`](scenes/ui/elements/leaderboard_container.tscn)
- Node editor (reusable)
  - Graph control: [`scripts/ui/nodegraph/node_graph.gd`](scripts/ui/nodegraph/node_graph.gd) — conversions and spawn helpers.
  - Sticky context menus: [`scripts/ui/widgets/sticky_panel.gd`](scripts/ui/widgets/sticky_panel.gd)
  - Context menu: [`scripts/ui/nodegraph/context/node_context_menu.gd`](scripts/ui/nodegraph/context/node_context_menu.gd)
  - Port and node base: [`scripts/ui/nodegraph/node_port.gd`](scripts/ui/nodegraph/node_port.gd), [`scripts/ui/nodegraph/nodes/base_node.gd`](scripts/ui/nodegraph/nodes/base_node.gd)
  - Built-in nodes: value/math/minmax/clamp/fitness:
    - [`scripts/ui/nodegraph/nodes/value_node.gd`](scripts/ui/nodegraph/nodes/value_node.gd)
    - [`scripts/ui/nodegraph/nodes/math_node.gd`](scripts/ui/nodegraph/nodes/math_node.gd)
    - [`scripts/ui/nodegraph/nodes/minmax_node.gd`](scripts/ui/nodegraph/nodes/minmax_node.gd)
    - [`scripts/ui/nodegraph/nodes/clamp_node.gd`](scripts/ui/nodegraph/nodes/clamp_node.gd)
    - [`scripts/ui/nodegraph/nodes/fitness_node.gd`](scripts/ui/nodegraph/nodes/fitness_node.gd)

How the node editor works (summary)
- Right-click in the graph -> context menu (`NodeContextMenu`) is created and positioned using a single viewport/screen point.
- `NodeGraph.screen_to_graph_local(screen_pos: Vector2)` converts that point once for node placement.
- `StickyPanel.popup_at_screen(screen_pos: Vector2)` converts once to parent-local and corrects for content inset so the visible menu aligns with the cursor.
- Nodes expose `evaluate()` and `evaluate_output()` patterns; Fitness node triggers `evaluate_fitness()` on the graph and reports parse errors back to the popup status.

Common tasks & file locations
- Add Node Editor toggle to HUD: edit [`scripts/ui/hud_setup.gd`](scripts/ui/hud_setup.gd) and ensure the toggle scene is added to the `BottomBar` child of `UIFrame`.
- Edit node visuals: create/adjust `.tscn` files in `scenes/ui/nodegraph/nodes/` and attach the corresponding `scripts/ui/nodegraph/nodes/*.gd`.
- Save/load graphs: NodeEditorPopup uses FileDialog (see [`scripts/ui/nodegraph/node_editor_popup.gd`](scripts/ui/nodegraph/node_editor_popup.gd)).

Debug checklist (paste console lines when debugging placement)
- [NodeGraph] RIGHT CLICK vp_mouse={vp_mouse} graph_local={graph_local} ev.position(local)={ev.position}
- [NodeGraph] parenting menu to menu_parent={menu_parent}
- [StickyPanel] popup_at_screen: parent={parent} screen_pos={screen_pos} local_pos={local_pos}
- [StickyPanel] popup_at_screen: adjusted for content offset delta={delta} new_local={new_local} final_pos={position}
- [NodeContextMenu] setup: screen={screen_pos} graph_local={graph_local} graph={graph}

Known issues / TODOs
- Some scripts required small Godot 4 fixes (use `@export`, `await` instead of `yield`, consistent class_name). See `hud_setup.gd` and StickyPanel for previous linter fixes.
- Node visuals (.tscn) are minimal stubs; wire UI elements (labels, port containers) to the node scripts.
- Fitness apply reporting: connect `FitnessNode.apply_requested` to `NodeEditorPopup.set_status()` to show parse errors inline.

Contact points in code (quick links)
- NodeGraph: [`scripts/ui/nodegraph/node_graph.gd`](scripts/ui/nodegraph/node_graph.gd)
- Sticky menus: [`scripts/ui/widgets/sticky_panel.gd`](scripts/ui/widgets/sticky_panel.gd)
- DataBroker: [`scripts/telemetry/dataBroker.gd`](scripts/telemetry/dataBroker.gd)
- AgentManager: [`scripts/manager/agentManager.gd`](scripts/manager/agentManager.gd)
- HUD setup: [`scripts/ui/hud_setup.gd`](scripts/ui/hud_setup.gd)

License & contribution
- This project is a private game dev repo. Add a LICENSE file if you want explicit sharing rules.

End.
