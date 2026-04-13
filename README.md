# todo_pile

A Neovim plugin that manages a **LIFO stack of todos anchored to code positions**.  
Each todo remembers the file and line where it was created and displays a marker in the sign column whenever that file is open.

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) _(optional)_ — used for the picker UI; falls back to `vim.ui.select` when not available

## Installation

### lazy.nvim

```lua
{
  "Mitra98t/TodoPile",
  dependencies = { "folke/snacks.nvim" },  -- optional, remove if not using snacks in favor of default picker
  config = function()
    require("todo_pile").setup()
  end,
}
```

## Configuration

Call `setup()` once, optionally passing a config table. All fields are optional.

```lua
require("todo_pile").setup({
  -- Symbol displayed in the sign column next to a todo's line.
  -- Any string up to 2 characters works (single emoji included).
  sign_text = "●",              -- default: "●"

  -- Highlight applied to the sign column marker.
  -- Accepts a highlight group name or a hex color string.
  sign_hl = "DiagnosticHint",   -- default: "DiagnosticHint"
  -- sign_hl = "#ff8800",        -- hex color alternative

  -- When true, each todo's first letter is used as its sign column marker
  -- instead of sign_text. Mutually exclusive with sign_text — a warning is
  -- shown at startup if both are set.
  sign_first_letter = false,    -- default: false

  -- When true, popping the top todo automatically jumps to the new top.
  jump_after_pop = true,        -- default: true

  -- When true, the todo text is shown as ghost (virtual) text at the end of
  -- its line. Uses the TodoPileGhostText highlight group (linked to Comment
  -- by default, override it in your colorscheme config if needed).
  ghost_text = false,           -- default: false
})
```

## Commands

| Command                 | Description                                                                                   |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| `:TodoPileAdd [text]`   | Add a todo at the cursor position. If `text` is omitted a prompt is shown.                    |
| `:TodoPilePop`          | Remove the most recent todo. Jumps to the new top if `jump_after_pop` is enabled.             |
| `:TodoPileJump`         | Jump to the file and line of the most recent todo without removing it.                        |
| `:TodoPileList`         | Open a picker listing all todos. Select one to navigate to it.                                |
| `:TodoPileClose`        | Open a picker listing all todos. Select one to delete it.                                     |
| `:TodoPileReorder`      | Open a floating window to manually reorder the stack.                                         |
| `:TodoPileClearProject` | Delete all todos whose files belong to the current working directory (asks for confirmation). |

### Reorder window keymaps

| Key                  | Action                |
| -------------------- | --------------------- |
| `<C-k>` / `<C-Up>`   | Move item up          |
| `<C-j>` / `<C-Down>` | Move item down        |
| `<CR>`               | Save new order        |
| `q` / `<Esc>`        | Cancel without saving |

## Example keymap configuration

```lua
-- Suggested keymaps (adjust to your preference)
local map = vim.keymap.set

-- Add a todo at the current position (prompts for text)
map("n", "<leader>ta", "<cmd>TodoPileAdd<cr>",     { desc = "Todo: add" })

-- Close (pop) the top todo and jump to the new top
map("n", "<leader>tx", "<cmd>TodoPilePop<cr>",     { desc = "Todo: pop top" })

-- Jump to the top todo without removing it
map("n", "<leader>tj", "<cmd>TodoPileJump<cr>",    { desc = "Todo: jump to top" })

-- Browse and navigate all todos
map("n", "<leader>tl", "<cmd>TodoPileList<cr>",    { desc = "Todo: list" })

-- Browse and selectively close a todo
map("n", "<leader>tc", "<cmd>TodoPileClose<cr>",   { desc = "Todo: close one" })

-- Reorder the stack
map("n", "<leader>tr", "<cmd>TodoPileReorder<cr>", { desc = "Todo: reorder" })

-- Clear all todos for the current project
map("n", "<leader>tX", "<cmd>TodoPileClearProject<cr>", { desc = "Todo: clear project" })
```

### Full lazy.nvim spec with keymaps

```lua
{
  dir = "~/dev/nvim/todo_pile",
  dependencies = { "folke/snacks.nvim" },
  keys = {
    { "<leader>ta", "<cmd>TodoPileAdd<cr>",          desc = "Todo: add" },
    { "<leader>tx", "<cmd>TodoPilePop<cr>",          desc = "Todo: pop top" },
    { "<leader>tj", "<cmd>TodoPileJump<cr>",         desc = "Todo: jump to top" },
    { "<leader>tl", "<cmd>TodoPileList<cr>",         desc = "Todo: list" },
    { "<leader>tc", "<cmd>TodoPileClose<cr>",        desc = "Todo: close one" },
    { "<leader>tr", "<cmd>TodoPileReorder<cr>",      desc = "Todo: reorder" },
    { "<leader>tX", "<cmd>TodoPileClearProject<cr>", desc = "Todo: clear project" },
  },
  config = function()
    require("todo_pile").setup({
      sign_text      = "●",
      sign_hl        = "DiagnosticHint",
      jump_after_pop = true,
    })
  end,
}
```

## Data storage

Todos are persisted as JSON at:

```
$XDG_DATA_HOME/nvim/todo_pile.json
```

(`vim.fn.stdpath("data")` on your system — typically `~/.local/share/nvim/todo_pile.json`.)

The file is rewritten on every change. Deleting it resets the pile.
