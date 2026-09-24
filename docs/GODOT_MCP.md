# Godot MCP Pro

Godot MCP Pro connects to the running Godot editor. Keep the Hoopclone editor open while an agent uses its tools.

## Setup

1. In Godot, open **Project > Project Settings > Plugins** and enable **Godot MCP Pro**. Its MCP Pro bottom panel should show a connection on port 6505.
2. The Node server lives outside this repository at `C:/Users/Kariim/Downloads/godot-mcp-pro-v1.16.0/server`.
3. Build it from that folder with `npm install` followed by `npm run build`.
4. Start an MCP-capable client from this project. The ignored `.mcp.json` starts `server/build/index.js` and uses port 6505.

## Test

With the editor open and the client restarted after configuration, call `list_scene_tree`. A response from the open editor proves the connection.

## Version and CI

The project CI remains on Godot 4.3-stable and runs `tests/godot/run_tests.gd` headlessly. CI cannot host editor MCP. MCP Pro is used with the local Godot editor; the current local editor is Godot 4.7-stable, which meets MCP Pro's 4.4+ requirement.
