# csharp-toolkit.nvim

A Neovim plugin for managing C# projects and solutions.

## Features

- Create new C# projects with template selection (Blazor Server, Blazor WASM, Razor Class Library, Class Library)
- Create and manage solutions (.sln and .slnx formats)
- Add/remove projects from solutions
- Automatic solution detection

## Requirements

- Neovim 0.9+
- .NET SDK installed (`dotnet` CLI available)

## Installation

### lazy.nvim

```lua
{
  "andres-m-rodriguez/csharp-toolkit.nvim",
  ft = { "cs", "razor" },
  config = function()
    require("csharp-toolkit").setup()
  end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:CSNewProject` | Create a new C# project |
| `:CSNewSolution` | Create a new solution |
| `:CSAddToSolution` | Add a project to the solution |
| `:CSRemoveFromSolution` | Remove a project from the solution |
| `:CSListProjects` | List all projects in the solution |

## Default Keymaps

| Keymap | Command |
|--------|---------|
| `<leader>cp` | Create new project |
| `<leader>cs` | Create new solution |
| `<leader>ca` | Add project to solution |
| `<leader>cr` | Remove project from solution |

## Configuration

```lua
require("csharp-toolkit").setup({
  -- Disable default keymaps
  keymaps = false,

  -- Or customize them
  keymaps = {
    new_project = "<leader>cp",
    new_solution = "<leader>cs",
    add_to_solution = "<leader>ca",
    remove_from_solution = "<leader>cr",
  },

  -- Add custom templates
  templates = {
    { name = "Blazor Server App", template = "blazorserver", icon = "󰐷" },
    { name = "Blazor WebAssembly App", template = "blazorwasm", icon = "󰖟" },
    { name = "Razor Class Library", template = "razorclasslib", icon = "󰰎" },
    { name = "Class Library", template = "classlib", icon = "󰆧" },
    { name = "Console App", template = "console", icon = "" },
    { name = "Web API", template = "webapi", icon = "󰒍" },
  },
})
```

## License

MIT
