# The Godot MCP tools are not connected to Claude Code yet

The `godot_mcp` addon is installed and enabled inside the Godot project
(`addons/godot_mcp`, autoload `MCPGameBridge`, port 6550), but no matching MCP
server is registered with Claude Code. There is no `.mcp.json` in the project
folder. So the `godot_docs` tool and the Godot run/test tools that CLAUDE.md
asks for do not currently exist in a Claude Code session.

Why: On 2026-09-23 Jarman asked me to use the Godot tools to report the project
name and version. I searched for them, found none, and had to fall back to
reading `project.godot` by hand.

Update 2026-09-23: missing MCP tools are not an excuse to skip testing. The
Godot binary itself is on this machine and runs the game from Bash - see
[[godot-cli-runs-the-game-headless]].

How to apply: If a task needs `godot_docs` or the Godot run/test tools, do not
pretend to call them and do not silently skip the "run the game and test it"
rule. Say plainly that the tools are missing, read `project.godot` or the source
files directly instead, and offer to register the MCP server (a `.mcp.json` in
the project, or `claude mcp add`) with the Godot editor open and the plugin
active. Delete this note once the tools show up in a session.
