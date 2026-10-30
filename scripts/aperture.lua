-- aperture-local lives on the box, so this file belongs in the Mac's
-- ~/.config/rex/ beside sand.lua and is loaded with require("aperture").
-- The action runs on the Mac but asks the focused session's server, the box,
-- to start the rebuild. A rebuild compiles for minutes, past an action's 30
-- second limit, so it gets a pane of its own instead of an exec the action
-- waits on.

-- aperture-local isn't on the box's login PATH; it comes from .zshrc.
local rebuild = [[exec "$HOME/projects/aperture-scripts/aperture-local" rebuild]]

rex.action{
  name     = "aperture_rebuild",
  title    = "Rebuild local Aperture",
  category = "aperture",
  description = "Run aperture-local rebuild on the focused session's server, in a pane below the focused block.",
  run      = function(ctx)
    if ctx.session_id == nil then error("aperture: no focused session", 0) end
    -- A server handle offers call but not exec, so the pane comes from the
    -- API rather than rex run.
    local server = rex
    if ctx.server ~= nil then server = rex.server(ctx.server) end
    if server == nil then error("aperture: no server " .. tostring(ctx.server), 0) end

    -- A server handle's stream starts detached, and session methods on it
    -- fail with conflict until it attaches.
    local _, err = server.call("session.attach", { session_id = ctx.session_id })
    if err ~= nil then error("aperture: attach: " .. tostring(err), 0) end
    local r, err = server.call("session.new_split", {
      session_id = ctx.session_id,
      anchor_id  = ctx.block_id,
      direction  = "vertical",
      side       = "after",
      ratio      = 0.6,
      focus      = true,
      layout     = { block = {
        flavor  = "com.superlogical.terminal.shell",
        label   = "aperture rebuild",
        options = {
          shell   = "none",
          command = { "/bin/sh", "-c", rebuild },
          exit    = { on_completion = false },
        },
      } },
    })
    if r == nil then error("aperture: " .. tostring(err), 0) end
    return r
  end,
}
rex.bind("cmd+shift+b", "aperture_rebuild")
