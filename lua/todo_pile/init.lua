-- init.lua
-- Public API and setup for todo_pile.
--
-- This module is the single entry point for consumers. It wires together
-- store, signs, picker, and reorder, and exposes one function per command.
-- Lazy-requires all sub-modules so nothing is loaded until first use.

local M = {}
M._setup_done    = false
M._jump_after_pop = true

-- Lazy accessors keep require() calls out of the module-level scope so the
-- plugin loads fast and sub-modules are only initialised when first needed.
local function store()   return require("todo_pile.store")   end
local function signs()   return require("todo_pile.signs")   end
local function picker()  return require("todo_pile.picker")  end
local function reorder() return require("todo_pile.reorder") end

-- Generate a simple unique id from timestamp + random suffix.
local function make_id()
  return tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
end

-- Re-paint signs in every loaded buffer. Called after any mutation that may
-- affect multiple files (pop, close, reorder, clear_project).
local function refresh_all_signs()
  local s  = store()
  local sg = signs()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      sg.refresh_buf(buf, s._todos)
    end
  end
end

-- Open the file and move the cursor to the todo's saved position.
-- Clamps the line to the actual buffer length in case the file has shrunk.
local function jump_to(todo)
  if not todo then
    vim.notify("todo_pile: stack is empty", vim.log.levels.INFO)
    return
  end
  if vim.fn.filereadable(todo.file) == 0 then
    vim.notify("todo_pile: file not found: " .. todo.file, vim.log.levels.WARN)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(todo.file))
  local line_count = vim.api.nvim_buf_line_count(0)
  local line = math.max(1, math.min(todo.line, line_count))
  local line_len = #(vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1] or "")
  local col = math.min(todo.col, line_len)
  vim.api.nvim_win_set_cursor(0, { line, col })
end

-- Push a new todo onto the stack at the cursor position.
-- If `text` is provided (e.g. from a command argument) it is used directly;
-- otherwise the user is prompted via vim.ui.input.
function M.add(text)
  local buf  = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    vim.notify("todo_pile: buffer has no file name", vim.log.levels.WARN)
    return
  end
  -- Capture position before the input prompt steals focus.
  local pos = vim.api.nvim_win_get_cursor(0) -- { 1-based line, 0-based col }

  local function commit(t)
    if not t or t == "" then return end
    local todo = {
      id         = make_id(),
      text       = t,
      file       = file,
      line       = pos[1],
      col        = pos[2],
      created_at = os.time(),
    }
    local s = store()
    s.add(todo)
    -- Only refresh the current buffer — other buffers are handled by BufEnter.
    signs().refresh_buf(buf, s._todos)
    vim.notify("todo_pile: added → " .. t, vim.log.levels.INFO)
  end

  if text and text ~= "" then
    commit(text)
  else
    -- vim.ui.input is intercepted by snacks.input when snacks is configured,
    -- giving the user a nicer floating prompt automatically.
    vim.ui.input({ prompt = "Todo: " }, commit)
  end
end

-- Remove the most recent todo and jump to the new top of the stack (if any).
function M.pop()
  local item = store().pop()
  if not item then
    vim.notify("todo_pile: stack is empty", vim.log.levels.INFO)
    return
  end
  refresh_all_signs()
  vim.notify("todo_pile: closed → " .. item.text, vim.log.levels.INFO)
  if M._jump_after_pop then
    jump_to(store().peek())
  end
end

-- Jump to the file and line of the most recent todo without removing it.
function M.jump()
  jump_to(store().peek())
end

-- Open the snacks picker to browse all todos; Enter navigates to the selection.
function M.list()
  picker().list(store(), function(todo)
    jump_to(todo)
  end)
end

-- Open the snacks picker to choose which todo to delete.
function M.close()
  picker().close_picker(store(), function(todo)
    store().remove_by_id(todo.id)
    refresh_all_signs()
    vim.notify("todo_pile: closed → " .. todo.text, vim.log.levels.INFO)
  end)
end

-- Delete all todos whose files live under the current working directory.
-- Asks for confirmation before proceeding because the action is irreversible.
function M.clear_project()
  local cwd   = vim.fn.getcwd()
  local count = 0
  for _, t in ipairs(store()._todos) do
    if vim.startswith(t.file, cwd .. "/") or t.file == cwd then
      count = count + 1
    end
  end
  if count == 0 then
    vim.notify("todo_pile: no todos in the current project", vim.log.levels.INFO)
    return
  end
  vim.ui.select(
    { "Yes, delete all", "No, cancel" },
    { prompt = string.format("Delete %d todo(s) in %s?", count, vim.fn.fnamemodify(cwd, ":~")) },
    function(choice)
      if choice ~= "Yes, delete all" then return end
      local removed = store().clear_project(cwd)
      refresh_all_signs()
      vim.notify(string.format("todo_pile: removed %d todo(s)", removed), vim.log.levels.INFO)
    end
  )
end

-- Open the floating reorder window.
function M.reorder()
  reorder().open(store(), refresh_all_signs)
end

-- ─── Setup ───────────────────────────────────────────────────────────────────

---@class TodoPileConfig
---@field sign_text?         string   Symbol shown in the sign column (default: "●")
---@field sign_hl?           string   Highlight group name OR hex color, e.g. "DiagnosticHint" or "#ff8800"
---@field sign_first_letter? boolean  Use each todo's first letter as its marker instead of sign_text (default: false)
---@field jump_after_pop?    boolean  Jump to the new top of the stack after popping (default: true)
---@field ghost_text?        boolean         Show the todo text as virtual text at the end of its line (default: false)
---@field ghost_text_prefix? boolean|string  Prefix shown before the todo in ghost text: true = marker glyph (default), false = none, string = literal (e.g. "TODO:")
---@field ghost_text_hl?     string          Highlight group name OR hex color for ghost text, e.g. "DiagnosticHint" or "#ff8800" (default: links to "Comment")

---@param opts? TodoPileConfig
function M.setup(opts)
  -- Guard against being called more than once (e.g. from multiple plugin managers).
  if M._setup_done then return end
  M._setup_done = true

  opts = opts or {}

  -- sign_first_letter and sign_text are mutually exclusive; warn if both are set.
  if opts.sign_first_letter and opts.sign_text then
    vim.notify(
      "todo_pile: sign_first_letter and sign_text are mutually exclusive; sign_first_letter takes precedence",
      vim.log.levels.WARN
    )
  end

  -- nil check with ~= false so omitting the option keeps the default of true.
  M._jump_after_pop = opts.jump_after_pop ~= false

  -- Configure the signs module with the chosen marker options.
  local sg = signs()
  sg.sign_text          = opts.sign_text or "●"
  sg.use_first_letter   = opts.sign_first_letter or false
  sg.ghost_text         = opts.ghost_text or false
  sg.ghost_text_prefix  = opts.ghost_text_prefix == nil and true or opts.ghost_text_prefix

  -- Define the TodoPileGhostText highlight group for virtual text.
  -- Accepts either a hex color string ("#rrggbb") or an existing highlight group name.
  local ghost_hl = opts.ghost_text_hl
  if ghost_hl then
    if ghost_hl:sub(1, 1) == "#" then
      vim.api.nvim_set_hl(0, "TodoPileGhostText", { fg = ghost_hl })
    else
      vim.api.nvim_set_hl(0, "TodoPileGhostText", { link = ghost_hl })
    end
  else
    vim.api.nvim_set_hl(0, "TodoPileGhostText", { link = "Comment", default = true })
  end

  -- Define the TodoPileSign highlight group.
  -- Accepts either a hex color string ("#rrggbb") or an existing highlight group name.
  local sign_hl = opts.sign_hl or "DiagnosticHint"
  if sign_hl:sub(1, 1) == "#" then
    vim.api.nvim_set_hl(0, "TodoPileSign", { fg = sign_hl, default = true })
  else
    vim.api.nvim_set_hl(0, "TodoPileSign", { link = sign_hl, default = true })
  end

  -- Load persisted todos and paint signs on any already-open buffers.
  local s = store()
  s.load()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      sg.refresh_buf(buf, s._todos)
    end
  end
end

return M
