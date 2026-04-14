-- reorder.lua
-- Floating window UI for manually reordering the todo stack.
--
-- Opens a scratch buffer listing todos (newest first = index 1 = top of stack).
-- The user moves items with <C-k/j> or <C-Up/Down>; <CR> saves the new order.
--
-- Correctness relies on keeping `_order` — the authoritative id-ordered list —
-- in sync with the buffer lines at all times. Every move swaps both the buffer
-- lines and the corresponding `_order` entries atomically, so the line index
-- always maps 1:1 to the todo in `_order`.

local M = {}

-- Current display order (index 1 = top of stack / most recent).
-- Populated on open, mutated on every move, consumed on save.
local _order = {}
local _buf   = nil
local _win   = nil

-- Swap lines `row` and `row + direction` in both the buffer and `_order`.
-- `row` is 1-based (as returned by nvim_win_get_cursor).
local function move_line(direction)
  local row     = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
  local new_row = row + direction
  if new_row < 1 or new_row > #_order then return end

  -- Compute 0-based indices for nvim_buf_get/set_lines.
  local lo = math.min(row, new_row) - 1
  local hi = math.max(row, new_row) - 1

  local line_lo = vim.api.nvim_buf_get_lines(_buf, lo, lo + 1, false)[1]
  local line_hi = vim.api.nvim_buf_get_lines(_buf, hi, hi + 1, false)[1]

  -- Swap the two lines in the buffer (replaces the range [lo, hi+1)).
  vim.api.nvim_buf_set_lines(_buf, lo, hi + 1, false, { line_hi, line_lo })

  -- Mirror the swap in _order so indices stay aligned with buffer rows.
  _order[row], _order[new_row] = _order[new_row], _order[row]

  -- Keep the cursor on the moved item.
  vim.api.nvim_win_set_cursor(0, { new_row, 0 })
end

local function close_win()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _buf, _win = nil, nil
end

---@param store_mod  table   require("todo_pile.store")
---@param dir        string  current working directory (project scope)
---@param refresh_fn fun()   callback that repaints signs after the order changes
function M.open(store_mod, dir, refresh_fn)
  local todos = store_mod.all_in_project(dir)
  if #todos == 0 then
    vim.notify("todo_pile: no todos to reorder in this project", vim.log.levels.INFO)
    return
  end

  -- Deep-copy so we never mutate store data until the user confirms.
  _order = vim.deepcopy(todos)

  -- Size the window to fit the list, capped to leave a margin around the editor.
  local width  = math.min(60, vim.o.columns - 4)
  local height = math.min(#todos, vim.o.lines - 6)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  _buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
  vim.bo[_buf].buftype   = "nofile"
  vim.bo[_buf].bufhidden = "wipe"

  -- Populate buffer with one line per todo (text only — ids live in _order).
  local lines = {}
  for _, todo in ipairs(_order) do
    lines[#lines + 1] = todo.text
  end
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)

  _win = vim.api.nvim_open_win(_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Reorder Todo Pile (project) ",
    title_pos  = "center",
    footer     = " <C-k/j> move  <CR> save  q cancel ",
    footer_pos = "center",
  })

  local opts = { buffer = _buf, nowait = true, silent = true }

  -- Movement keymaps — two equivalent pairs for comfort.
  vim.keymap.set("n", "<C-j>",    function() move_line(1)  end, opts)
  vim.keymap.set("n", "<C-k>",    function() move_line(-1) end, opts)
  vim.keymap.set("n", "<C-Down>", function() move_line(1)  end, opts)
  vim.keymap.set("n", "<C-Up>",   function() move_line(-1) end, opts)

  -- Confirm: reverse _order (display is newest-first; store expects oldest-first),
  -- then merge with non-project todos and write back to the store.
  vim.keymap.set("n", "<CR>", function()
    -- Collect todos that belong to other projects (preserve their order).
    local non_project = {}
    for _, t in ipairs(store_mod._todos) do
      if not (vim.startswith(t.file, dir .. "/") or t.file == dir) then
        non_project[#non_project + 1] = t
      end
    end
    -- Reverse display order to get oldest-first for storage.
    local reordered = {}
    for i = #_order, 1, -1 do
      reordered[#reordered + 1] = _order[i]
    end
    -- Non-project todos first, then reordered project todos (project = "newer" end).
    local merged = {}
    for _, t in ipairs(non_project) do merged[#merged + 1] = t end
    for _, t in ipairs(reordered)   do merged[#merged + 1] = t end
    store_mod._todos = merged
    store_mod.save()
    refresh_fn()
    close_win()
    vim.notify("todo_pile: order saved", vim.log.levels.INFO)
  end, opts)

  -- Cancel without saving.
  vim.keymap.set("n", "q",     close_win, opts)
  vim.keymap.set("n", "<Esc>", close_win, opts)
end

return M
