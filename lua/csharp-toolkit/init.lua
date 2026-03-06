-- csharp-toolkit.nvim
-- A Neovim plugin for managing C# projects and solutions

local M = {}

local projects = require("csharp-toolkit.projects")
local solutions = require("csharp-toolkit.solutions")
local di = require("csharp-toolkit.di")

M.config = {
  -- Default keybindings (set to false to disable)
  keymaps = {
    new_project = "<leader>cp",    -- Create new project
    new_solution = "<leader>cs",   -- Create new solution
    add_to_solution = "<leader>ca", -- Add project to solution
    remove_from_solution = "<leader>cr", -- Remove project from solution
    add_reference = "<leader>cR",  -- Add project reference
    help = "<leader>ch",           -- Show help
    init_file = "<leader>ci",      -- Initialize empty C# file
    add_service = "<leader>cd",    -- Add DI service to class
    add_using = "<leader>cu",      -- Show available usings to import
  },
  -- Project templates (dotnet new templates)
  templates = {
    { name = "Blazor Server App", template = "blazorserver", icon = "󰐷" },
    { name = "Blazor WebAssembly App", template = "blazorwasm", icon = "󰖟" },
    { name = "Razor Class Library", template = "razorclasslib", icon = "󰰎" },
    { name = "Class Library", template = "classlib", icon = "󰆧" },
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register commands
  vim.api.nvim_create_user_command("CSNewProject", function()
    projects.create_project(M.config.templates)
  end, { desc = "Create a new C# project" })

  vim.api.nvim_create_user_command("CSNewSolution", function()
    solutions.create_solution()
  end, { desc = "Create a new solution" })

  vim.api.nvim_create_user_command("CSAddToSolution", function()
    solutions.add_project_to_solution()
  end, { desc = "Add project to solution" })

  vim.api.nvim_create_user_command("CSRemoveFromSolution", function()
    solutions.remove_project_from_solution()
  end, { desc = "Remove project from solution" })

  vim.api.nvim_create_user_command("CSListProjects", function()
    solutions.list_projects()
  end, { desc = "List projects in solution" })

  vim.api.nvim_create_user_command("CSAddReference", function()
    projects.add_reference()
  end, { desc = "Add project reference" })

  vim.api.nvim_create_user_command("CSRemoveReference", function()
    projects.remove_reference()
  end, { desc = "Remove project reference" })

  vim.api.nvim_create_user_command("CSListReferences", function()
    projects.list_references()
  end, { desc = "List project references" })

  vim.api.nvim_create_user_command("CSHelp", function()
    M.show_help()
  end, { desc = "Show C# toolkit help" })

  vim.api.nvim_create_user_command("CSInitFile", function()
    projects.init_file()
  end, { desc = "Initialize C# file with namespace and class" })

  vim.api.nvim_create_user_command("CSAddService", function()
    di.add_service()
  end, { desc = "Add DI service to class" })

  vim.api.nvim_create_user_command("CSAddUsing", function()
    di.show_usings()
  end, { desc = "Show available usings to import" })

  -- Set up keymaps
  if M.config.keymaps then
    local km = M.config.keymaps
    if km.new_project then
      vim.keymap.set("n", km.new_project, "<cmd>CSNewProject<cr>", { desc = "New C# project" })
    end
    if km.new_solution then
      vim.keymap.set("n", km.new_solution, "<cmd>CSNewSolution<cr>", { desc = "New solution" })
    end
    if km.add_to_solution then
      vim.keymap.set("n", km.add_to_solution, "<cmd>CSAddToSolution<cr>", { desc = "Add to solution" })
    end
    if km.remove_from_solution then
      vim.keymap.set("n", km.remove_from_solution, "<cmd>CSRemoveFromSolution<cr>", { desc = "Remove from solution" })
    end
    if km.add_reference then
      vim.keymap.set("n", km.add_reference, "<cmd>CSAddReference<cr>", { desc = "Add project reference" })
    end
    if km.help then
      vim.keymap.set("n", km.help, "<cmd>CSHelp<cr>", { desc = "C# toolkit help" })
    end
    if km.init_file then
      vim.keymap.set("n", km.init_file, "<cmd>CSInitFile<cr>", { desc = "Initialize C# file" })
    end
    if km.add_service then
      vim.keymap.set("n", km.add_service, "<cmd>CSAddService<cr>", { desc = "Add DI service" })
    end
    if km.add_using then
      vim.keymap.set("n", km.add_using, "<cmd>CSAddUsing<cr>", { desc = "Add using" })
    end
  end
end

-- Show help window with all keybinds
function M.show_help()
  local km = M.config.keymaps or {}

  local lines = {
    "╭─────────────────────────────────────────────╮",
    "│           C# Toolkit - Keybinds             │",
    "├─────────────────────────────────────────────┤",
    "│                                             │",
    "│  Files                                      │",
    string.format("│    %s  Initialize C# file              │", km.init_file and string.format("%-10s", km.init_file) or "disabled  "),
    string.format("│    %s  Add DI service                  │", km.add_service and string.format("%-10s", km.add_service) or "disabled  "),
    string.format("│    %s  Add using/import                │", km.add_using and string.format("%-10s", km.add_using) or "disabled  "),
    "│                                             │",
    "│  Projects                                   │",
    string.format("│    %s  Create new project              │", km.new_project and string.format("%-10s", km.new_project) or "disabled  "),
    string.format("│    %s  Add project reference           │", km.add_reference and string.format("%-10s", km.add_reference) or "disabled  "),
    "│                                             │",
    "│  Solutions                                  │",
    string.format("│    %s  Create new solution             │", km.new_solution and string.format("%-10s", km.new_solution) or "disabled  "),
    string.format("│    %s  Add project to solution         │", km.add_to_solution and string.format("%-10s", km.add_to_solution) or "disabled  "),
    string.format("│    %s  Remove from solution            │", km.remove_from_solution and string.format("%-10s", km.remove_from_solution) or "disabled  "),
    "│                                             │",
    "│  Commands                                   │",
    "│    :CSInitFile        Init file template    │",
    "│    :CSAddService      Add DI service        │",
    "│    :CSNewProject      Create project        │",
    "│    :CSNewSolution     Create solution       │",
    "│    :CSAddToSolution   Add to solution       │",
    "│    :CSRemoveFromSolution                    │",
    "│    :CSAddReference    Add reference         │",
    "│    :CSRemoveReference Remove reference      │",
    "│    :CSListProjects    List projects         │",
    "│    :CSListReferences  List references       │",
    "│                                             │",
    "│  Press q or <Esc> to close                  │",
    "╰─────────────────────────────────────────────╯",
  }

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Calculate window size and position
  local width = 47
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none",
  })

  -- Set keymaps to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

-- Expose modules for direct access
M.projects = projects
M.solutions = solutions
M.di = di

return M
