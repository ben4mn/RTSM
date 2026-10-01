extends Node
## Production-safe placeholder for the editor-only MCP game bridge.
##
## No runtime gameplay code depends on the automation bridge. Keeping this
## intentionally empty autoload preserves one project topology while allowing
## release exports to exclude `addons/godot_mcp/` completely.
