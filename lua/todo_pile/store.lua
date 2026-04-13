-- store.lua
-- Manages the in-memory todo list and its JSON persistence.
--
-- The list is an append-only array; newest item is always at index #_todos.
-- All mutations do a full rewrite of the JSON file — the list is small enough
-- that this is simpler and safer than partial updates.

local M = {}

M._todos = {} ---@type table[]

local DATA_PATH = vim.fn.stdpath("data") .. "/todo_pile.json"

-- Load todos from disk. Silently starts with an empty list on missing or
-- corrupt file so a bad JSON state never blocks the plugin from starting.
function M.load()
  local f = io.open(DATA_PATH, "r")
  if not f then
    M._todos = {}
    return
  end
  local raw = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.fn.json_decode, raw)
  M._todos = (ok and type(decoded) == "table") and decoded or {}
end

-- Persist the current todo list to disk.
function M.save()
  local f = io.open(DATA_PATH, "w")
  if not f then
    vim.notify("todo_pile: cannot write " .. DATA_PATH, vim.log.levels.ERROR)
    return
  end
  f:write(vim.fn.json_encode(M._todos))
  f:close()
end

-- Append a new todo to the top of the stack and persist.
function M.add(item)
  table.insert(M._todos, item)
  M.save()
  return item
end

-- Remove and return the most recent todo (top of stack).
-- Returns nil when the stack is empty.
function M.pop()
  if #M._todos == 0 then return nil end
  local item = table.remove(M._todos) -- table.remove with no index removes the last element
  M.save()
  return item
end

-- Remove a specific todo by its id. Returns true on success, false if not found.
function M.remove_by_id(id)
  for i, t in ipairs(M._todos) do
    if t.id == id then
      table.remove(M._todos, i)
      M.save()
      return true
    end
  end
  return false
end

-- Remove all todos whose file path is under `dir`.
-- Returns the number of todos that were removed.
function M.clear_project(dir)
  local kept    = {}
  local removed = 0
  for _, t in ipairs(M._todos) do
    if vim.startswith(t.file, dir .. "/") or t.file == dir then
      removed = removed + 1
    else
      kept[#kept + 1] = t
    end
  end
  if removed > 0 then
    M._todos = kept
    M.save()
  end
  return removed
end

-- Return the most recent todo without removing it. Returns nil if empty.
function M.peek()
  return M._todos[#M._todos]
end

-- Return a shallow-reversed copy of the todo list (newest first).
-- Used for display; does not mutate the canonical list.
function M.all_newest_first()
  local rev = {}
  for i = #M._todos, 1, -1 do
    rev[#rev + 1] = M._todos[i]
  end
  return rev
end

return M
