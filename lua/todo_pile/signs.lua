-- signs.lua
-- Manages extmark-based sign column markers for todos.
--
-- Each todo whose file matches the current buffer gets a sign on its line.
-- Signs are placed using nvim_buf_set_extmark with the `sign_text` option,
-- which renders text in the sign column without affecting buffer content.
--
-- Position resilience strategy:
--   Neovim extmarks automatically follow line/column changes as the buffer is
--   edited. We exploit this by recording the extmark id for each todo and
--   reading the updated position back via nvim_buf_get_extmark_by_id before
--   the extmarks are cleared. The caller (BufLeave autocmd) is responsible for
--   flushing those positions back to the store so they survive across sessions.

local M = {}

-- Extmark namespace shared across the plugin.
M.ns = vim.api.nvim_create_namespace("todo_pile")

-- Sign column text. Overridden by setup() via opts.sign_text.
M.sign_text = "●"

-- When true, each todo's first letter is used instead of sign_text.
-- Overridden by setup() via opts.sign_first_letter.
M.use_first_letter = false

-- When true, the todo text is rendered as virtual (ghost) text at the end of
-- its line using the TodoPileGhostText highlight group.
-- Overridden by setup() via opts.ghost_text.
M.ghost_text = false

-- Per-buffer map of todo_id → extmark_id for the currently placed marks.
-- Used by read_positions() to query Neovim for the live (post-edit) location.
M._marks = {} -- [bufnr] = { [todo_id] = extmark_id }

-- Refresh signs for a single buffer.
-- Clears all existing signs first so this is safe to call multiple times.
-- NOTE: call read_positions() *before* this if you want to capture updated
-- line numbers from the previous set of extmarks.
function M.refresh_buf(buf, todos)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local bufname = vim.api.nvim_buf_get_name(buf)
  if bufname == "" then return end -- unnamed/scratch buffers have no path to match against

  -- Wipe all previous signs placed by this plugin in this buffer.
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  M._marks[buf] = {}

  local line_count = vim.api.nvim_buf_line_count(buf)

  for _, todo in ipairs(todos) do
    if todo.file == bufname then
      -- Extmarks are 0-indexed; todos store 1-indexed lines.
      local zero_line = todo.line - 1
      -- Clamp to the actual buffer length in case the file shrank since the todo was created.
      zero_line = math.max(0, math.min(zero_line, line_count - 1))

      -- Determine the sign glyph: first letter of the todo text, or the configured symbol.
      local glyph = M.use_first_letter and todo.text:sub(1, 1) or M.sign_text

      -- Build the extmark options. virt_text is added only when ghost_text is enabled.
      -- Both sign and virtual text are placed in the same extmark to keep the
      -- namespace clean (one mark per todo per buffer).
      local mark_opts = {
        sign_text     = glyph,
        sign_hl_group = "TodoPileSign",
        priority      = 10,
      }
      if M.ghost_text then
        mark_opts.virt_text     = { { "  " .. todo.text, "TodoPileGhostText" } }
        mark_opts.virt_text_pos = "eol"
      end

      -- Place the extmark and record its id so read_positions() can find it later.
      local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, zero_line, 0, mark_opts)
      if ok then
        M._marks[buf][todo.id] = mark_id
      end
    end
  end
end

-- Read the current (post-edit) positions of all tracked extmarks in a buffer.
-- Returns a map { todo_id -> { line, col } } with 1-based line and 0-based col,
-- containing only the todos whose position has changed since they were placed.
-- Call this before refresh_buf() clears the extmarks.
function M.read_positions(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return {} end
  local marks = M._marks[buf]
  if not marks then return {} end

  local updates = {}
  for todo_id, mark_id in pairs(marks) do
    -- Returns { row, col } (0-based) or {} if the mark no longer exists.
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, mark_id, {})
    if pos and pos[1] ~= nil then
      updates[todo_id] = {
        line = pos[1] + 1, -- convert to 1-based to match store format
        col  = pos[2],
      }
    end
  end
  return updates
end

-- Remove all signs placed by this plugin across every loaded buffer.
-- Called on full resets (not normally needed in day-to-day use).
function M.clear_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
  end
  M._marks = {}
end

return M
