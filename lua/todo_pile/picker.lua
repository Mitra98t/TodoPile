-- picker.lua
-- Todo selection UI with snacks.nvim, telescope.nvim, and a vim.ui.select fallback.
--
-- Two operations are exposed:
--   list(todos, title, on_confirm)   — browse todos and navigate to the selected one
--   close_picker(todos, title, on_delete) — browse todos and delete the selected one
--
-- Picker preference order: snacks → telescope → vim.ui.select

local M = {}

-- ─── Snacks picker helpers ────────────────────────────────────────────────────

-- Build the items array consumed by Snacks.picker.
-- Each item carries a private _todo field forwarded to the confirm callback.
local function make_items(todos)
  local items = {}
  for i, todo in ipairs(todos) do
    local short_file = vim.fn.fnamemodify(todo.file, ":~:.") -- relative to home / cwd
    local date       = os.date("%m-%d %H:%M", todo.created_at)
    items[i] = {
      -- `text` is what Snacks fuzzy-matches against.
      text        = todo.text .. " " .. short_file,
      -- Fields used by the Snacks built-in jump action and file previewer.
      file        = todo.file,
      pos         = { todo.line, todo.col }, -- { 1-based line, 0-based col }
      preview     = "file",                  -- scroll the preview to pos
      -- Private payload forwarded to callbacks.
      _todo       = todo,
      _label      = todo.text,
      _short_file = short_file,
      _line       = todo.line,
      _date       = date,
    }
  end
  return items
end

-- Custom row renderer: "● <todo text padded to 40>  <file:line>  <date>"
-- Returns an array of { text, hl_group } pairs rendered left-to-right.
local function format_item(item, _picker)
  return {
    { "● ",                                           "TodoPileSign" },
    { string.format("%-40s", item._label:sub(1, 40)), "Normal"       },
    { "  "                                                            },
    { item._short_file .. ":" .. item._line,          "Comment"      },
    { "  "                                                            },
    { item._date,                                     "NonText"      },
  }
end

-- ─── vim.ui.select fallback ───────────────────────────────────────────────────

-- Build a plain string label for each todo, used by vim.ui.select.
local function make_select_labels(todos)
  local labels = {}
  for _, todo in ipairs(todos) do
    local short_file = vim.fn.fnamemodify(todo.file, ":~:.")
    labels[#labels + 1] = string.format("%-40s  %s:%d", todo.text:sub(1, 40), short_file, todo.line)
  end
  return labels
end

-- ─── Availability checks ─────────────────────────────────────────────────────

-- Returns the snacks module if it is loadable and exposes a picker, else nil.
local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker then
    return snacks
  end
end

-- Returns true if telescope.nvim is available.
local function get_telescope()
  local ok, tel = pcall(require, "telescope")
  if ok and tel then return true end
end

-- ─── Telescope implementation ─────────────────────────────────────────────────

local function telescope_pick(todos, title, on_confirm)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = todos,
      entry_maker = function(todo)
        local short_file = vim.fn.fnamemodify(todo.file, ":~:.")
        return {
          value    = todo,
          display  = string.format("%-40s  %s:%d", todo.text:sub(1, 40), short_file, todo.line),
          ordinal  = todo.text .. " " .. short_file,
          filename = todo.file,
          lnum     = todo.line,
          col      = todo.col,
        }
      end,
    }),
    sorter    = conf.generic_sorter({}),
    previewer = conf.file_previewer({}),
    attach_mappings = function(prompt_bufnr, _map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel and on_confirm then on_confirm(sel.value) end
      end)
      return true
    end,
  }):find()
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- Open a picker listing the given todos. Selecting an item calls on_confirm(todo).
function M.list(todos, title, on_confirm)
  if #todos == 0 then
    vim.notify("todo_pile: no todos", vim.log.levels.INFO)
    return
  end

  local snacks = get_snacks()
  if snacks then
    snacks.picker.pick("todo_pile_list", {
      title   = " " .. title,
      items   = make_items(todos),
      format  = format_item,
      confirm = function(picker, item)
        picker:close()
        if item and on_confirm then on_confirm(item._todo) end
      end,
    })
  elseif get_telescope() then
    telescope_pick(todos, title, on_confirm)
  else
    -- Fallback: vim.ui.select with a plain-text label per todo.
    vim.ui.select(make_select_labels(todos), { prompt = title .. ": navigate to" }, function(_, idx)
      if idx and on_confirm then on_confirm(todos[idx]) end
    end)
  end
end

-- Open a picker for selective deletion. Selecting an item calls on_delete(todo).
function M.close_picker(todos, title, on_delete)
  if #todos == 0 then
    vim.notify("todo_pile: no todos to close", vim.log.levels.INFO)
    return
  end

  local snacks = get_snacks()
  if snacks then
    snacks.picker.pick("todo_pile_close", {
      title   = " " .. title,
      items   = make_items(todos),
      format  = format_item,
      confirm = function(picker, item)
        picker:close()
        if item and on_delete then on_delete(item._todo) end
      end,
    })
  elseif get_telescope() then
    telescope_pick(todos, title, on_delete)
  else
    -- Fallback: vim.ui.select with the same plain-text labels.
    vim.ui.select(make_select_labels(todos), { prompt = title .. ": select to close" }, function(_, idx)
      if idx and on_delete then on_delete(todos[idx]) end
    end)
  end
end

return M
