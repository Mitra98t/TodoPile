-- plugin/todo_pile.lua
-- Registers user commands and the BufEnter autocommand at startup.
--
-- This file runs automatically when Neovim loads the plugin (before setup() is
-- called). All requires are deferred so no sub-module is loaded until the
-- corresponding command is actually invoked.

-- ─── Commands ────────────────────────────────────────────────────────────────

-- Add a todo anchored to the current cursor position.
-- Accepts an optional inline argument: :TodoPileAdd fix the null check
-- If no argument is given, a prompt is shown instead.
vim.api.nvim_create_user_command("TodoPileAdd",
  function(opts)
    local text = opts.args ~= "" and opts.args or nil
    require("todo_pile").add(text)
  end,
  { nargs = "*", desc = "todo_pile: add todo at cursor position" })

-- Remove the most recent todo without any UI.
vim.api.nvim_create_user_command("TodoPilePop",
  function() require("todo_pile").pop() end,
  { desc = "todo_pile: remove top of todo stack" })

-- Jump to the file/line of the most recent todo.
vim.api.nvim_create_user_command("TodoPileJump",
  function() require("todo_pile").jump() end,
  { desc = "todo_pile: jump to top of todo stack" })

-- Browse todos in a picker; Enter navigates to the selection.
-- Use ! to show todos from all projects instead of just the current one.
vim.api.nvim_create_user_command("TodoPileList",
  function(opts) require("todo_pile").list({ global = opts.bang }) end,
  { bang = true, desc = "todo_pile: list todos (! for all projects)" })

-- Choose a specific todo to delete via picker.
-- Use ! to show todos from all projects instead of just the current one.
vim.api.nvim_create_user_command("TodoPileClose",
  function(opts) require("todo_pile").close({ global = opts.bang }) end,
  { bang = true, desc = "todo_pile: select a todo to close (! for all projects)" })

-- Populate the quickfix list with todos in the current project.
vim.api.nvim_create_user_command("TodoPileQuickfix",
  function() require("todo_pile").quickfix() end,
  { desc = "todo_pile: populate quickfix list with project todos" })

-- Open the floating window to manually reorder the stack.
vim.api.nvim_create_user_command("TodoPileReorder",
  function() require("todo_pile").reorder() end,
  { desc = "todo_pile: reorder todo stack in floating window" })

-- Delete all todos belonging to the current working directory (with confirmation).
vim.api.nvim_create_user_command("TodoPileClearProject",
  function() require("todo_pile").clear_project() end,
  { desc = "todo_pile: delete all todos in the current project" })

-- ─── Autocommand ─────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("todo_pile", { clear = true })

-- Repaint sign column markers whenever a buffer is entered.
-- store._todos is an empty table before setup() runs, so this is a safe no-op
-- until the plugin is fully initialised.
vim.api.nvim_create_autocmd("BufEnter", {
  group    = group,
  callback = function(ev)
    local s  = require("todo_pile.store")
    local sg = require("todo_pile.signs")
    sg.refresh_buf(ev.buf, s._todos)
  end,
  desc = "todo_pile: refresh signs on BufEnter",
})

-- Flush live extmark positions back to the store before leaving a buffer.
-- Neovim automatically tracks extmark positions as lines are added/removed,
-- so reading them here captures any edits made during the session and keeps
-- the stored line numbers in sync with the actual file content.
vim.api.nvim_create_autocmd("BufLeave", {
  group    = group,
  callback = function(ev)
    local s       = require("todo_pile.store")
    local sg      = require("todo_pile.signs")
    local updates = sg.read_positions(ev.buf)

    local changed = false
    for _, todo in ipairs(s._todos) do
      local pos = updates[todo.id]
      if pos and (pos.line ~= todo.line or pos.col ~= todo.col) then
        todo.line = pos.line
        todo.col  = pos.col
        changed   = true
      end
    end

    -- Only rewrite the JSON file if something actually moved.
    if changed then s.save() end
  end,
  desc = "todo_pile: flush extmark positions to store on BufLeave",
})
