-- sand runs on the Mac, so this file belongs in the Mac's ~/.config/rex/ and
-- is loaded from the Mac's init.lua with require("sand"). Actions run on the
-- client's own server, so rex.exec here runs on the Mac even while the focused
-- session lives on the box. sand prompts and streams agent output for minutes,
-- past an action's 30 second limit, so each run gets its own local session
-- instead of an exec the action waits on.

local terminal = "com.superlogical.terminal"

-- Commands that take --worktree, per the sand README.
local takes_worktree = {
  status = true, up = true, push = true, sign = true,
  ["comments pull"] = true, ["comments push"] = true, ["ci pull"] = true,
  ["pr create"] = true, ["pr review"] = true,
}

-- The app doesn't put rex on the login PATH, but this shell's parent is the
-- Mac's Rex server, which is the rex binary.
local find_rex = [[
r=$(command -v rex) || r=$(ps -o comm= -p $PPID)
case ${r##*/} in rex) print -r -- "$r"; exit ;; esac
echo "no rex CLI: not on PATH and the server is $r" >&2; exit 127
]]

-- rex_path returns the Mac's rex binary.
local function rex_path()
  local r, err = rex.exec({ "/bin/zsh", "-lc", find_rex }, { timeout = 10 })
  if r == nil then error(err, 0) end
  if not r.ok then error(r.stderr, 0) end
  return (r.stdout:gsub("%s+$", ""))
end

-- The pane runs sand in an interactive zsh, because sand, gh and ~/.local/bin
-- come from .zshrc, which rex new's default login shell never reads. When sand
-- exits the pane kills its own session, which would otherwise stay behind
-- empty; on failure it waits for a key first so the error can be read.
local run_and_close = [[
rex=$1; shift
"$@"; s=$?
if (( s )); then print -n "\nsand exited $s; press a key to close"; read -sk1; fi
"$rex" kill "$REX_SESSION"
]]

-- focused_cwd returns the directory of the focused box pane's foreground
-- program, and the box home it sits under.
local function focused_cwd(ctx)
  if ctx.block_id == nil then return nil end
  local p = rex.block.call(terminal, "process", { block_id = ctx.block_id })
  if p == nil or p.foreground == nil then return nil end
  return p.foreground.cwd, p.home
end

-- mac_checkout mirrors a box path onto the Mac's home: box ~/projects/foo is
-- Mac ~/projects/foo. sand has no setting for where Mac checkouts live.
-- ponytail: assumes identical layout under both homes; add a map if they diverge.
local function mac_checkout(box_cwd, box_home)
  if box_cwd == nil or box_home == nil then return nil end
  if box_cwd:sub(1, #box_home + 1) ~= box_home .. "/" then return nil end
  return os.getenv("HOME") .. box_cwd:sub(#box_home + 1)
end

rex.action{
  name     = "sand",
  title    = "Run sand…",
  category = "sand",
  description = "Run a sand command on the Mac in its own session, in the Mac checkout matching the focused box pane. Defaults --worktree to that pane's directory.",
  args     = { argv = "array", worktree = "string?", cwd = "string?" },
  run      = function(ctx, args)
    local argv = args.argv or {}
    if #argv == 0 then error("sand: argv is empty", 0) end

    local box_cwd, box_home = focused_cwd(ctx)
    local cwd
    if box_home ~= nil and box_home == os.getenv("HOME") then
      -- The focused pane is on the Mac: it already sits in the checkout, and
      -- its path means nothing to the box, so it can't be a --worktree.
      cwd, box_cwd = args.cwd or box_cwd, nil
    else
      cwd = args.cwd or mac_checkout(box_cwd, box_home)
    end
    if cwd == nil then
      error("sand: no Mac checkout for the focused pane (" .. tostring(box_cwd) .. "); pass cwd=", 0)
    end
    local d = rex.exec({ "test", "-d", cwd })
    if d == nil or not d.ok then error("sand: no Mac checkout at " .. cwd .. "; pass cwd=", 0) end

    local cmd = { "sand" }
    for _, a in ipairs(argv) do cmd[#cmd + 1] = a end
    local verb = argv[1] .. (argv[2] and (" " .. argv[2]) or "")
    if takes_worktree[verb] or takes_worktree[argv[1]] then
      local wt = args.worktree or box_cwd
      if wt ~= nil and wt ~= "" then
        cmd[#cmd + 1] = "--worktree"
        cmd[#cmd + 1] = wt
      end
    end

    local rex_bin = rex_path()
    local new = { rex_bin, "new", table.concat(cmd, " "), "--json",
                  "-c", cwd, "--shell", "none",
                  "--", "/bin/zsh", "-ic", run_and_close, "zsh", rex_bin }
    for _, a in ipairs(cmd) do new[#new + 1] = a end
    -- REX_* cleared so rex new targets the Mac's server, not the box.
    local r, err = rex.exec(new, {
      timeout = 20,
      env = { REX_SERVER = false, REX_SESSION = false, REX_BLOCK = false, REX_CLIENT = false },
    })
    if r == nil then error(err, 0) end
    if not r.ok then error("rex new: " .. r.stderr, 0) end

    local s = rex.json.decode(r.stdout)
    if s == nil or s.session_id == nil then error("rex new returned no session: " .. r.stdout, 0) end
    rex.client.queue("session.select", { session_id = s.session_id })
    return { session_id = s.session_id }
  end,
}



-- cmd+; then a letter.
rex.bind("cmd+shift+s", "sand", { argv = { "status" } })
rex.bind("cmd+shift+u", "sand", { argv = { "up", "-y" } })
rex.bind("cmd+shift+g", "sand", { argv = { "sign", "--push", "-y" } })
rex.bind("cmd+shift+c", "sand", { argv = { "comments", "pull", "--no-agent" } })
rex.bind("cmd+shift+i", "sand", { argv = { "ci", "pull", "--no-agent" } })
rex.bind("cmd+shift+p", "sand", { argv = { "pr", "create" } })
rex.bind("cmd+shift+r", "sand", { argv = { "pr", "review" } })
rex.bind("cmd+shift+n", "sand", { argv = { "issue", "create" } })
rex.bind("cmd+shift+x", "sand", { argv = { "shot" } })
