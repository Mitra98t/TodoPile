-- picker.lua
-- Todo selection UI with a snacks.nvim picker and a vim.ui.select fallback.
--
-- Two operations are exposed:
--   list()         — browse todos and navigate to the selected one
--   close_picker() — browse todos and delete the selected one
--
-- If snacks.nvim is not available the same operations work via vim.ui.select,
-- which itself can be overridden by telescope, fzf-lua, etc.

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

-- ─── Availability check ───────────────────────────────────────────────────────

-- Returns the snacks module if it is loadable and exposes a picker, else nil.
local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker then
    return snacks
  end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- Open a picker listing all todos. Selecting an item calls on_confirm(todo).
function M.list(store, on_confirm)
  local todos = store.all_newest_first()
  if #todos == 0 then
    vim.notify("todo_pile: no todos", vim.log.levels.INFO)
    return
  end

  local snacks = get_snacks()
  if snacks then
    snacks.picker.pick("todo_pile_list", {
      title   = " Todo Pile",
      items   = make_items(todos),
      format  = format_item,
      confirm = function(picker, item)
        picker:close()
        if item and on_confirm then on_confirm(item._todo) end
      end,
    })
  else
    -- Fallback: vim.ui.select with a plain-text label per todo.
    vim.ui.select(make_select_labels(todos), { prompt = "Todo Pile: navigate to" }, function(_, idx)
      if idx and on_confirm then on_confirm(todos[idx]) end
    end)
  end
end

-- Open a picker for selective deletion. Selecting an item calls on_delete(todo).
function M.close_picker(store, on_delete)
  local todos = store.all_newest_first()
  if #todos == 0 then
    vim.notify("todo_pile: no todos to close", vim.log.levels.INFO)
    return
  end

  local snacks = get_snacks()
  if snacks then
    snacks.picker.pick("todo_pile_close", {
      title   = " Close Todo",
      items   = make_items(todos),
      format  = format_item,
      confirm = function(picker, item)
        picker:close()
        if item and on_delete then on_delete(item._todo) end
      end,
    })
  else
    -- Fallback: vim.ui.select with the same plain-text labels.
    vim.ui.select(make_select_labels(todos), { prompt = "Todo Pile: select to close" }, function(_, idx)
      if idx and on_delete then on_delete(todos[idx]) end
    end)
  end
end

return M
