-- csharp-toolkit.nvim
-- A Neovim plugin for managing C# projects and solutions

local M = {}

local projects = require("csharp-toolkit.projects")
local solutions = require("csharp-toolkit.solutions")

M.config = {
  -- Default keybindings (set to false to disable)
  keymaps = {
    new_project = "<leader>cp",    -- Create new project
    new_solution = "<leader>cs",   -- Create new solution
    add_to_solution = "<leader>ca", -- Add project to solution
    remove_from_solution = "<leader>cr", -- Remove project from solution
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
  end
end

-- Expose modules for direct access
M.projects = projects
M.solutions = solutions

return M
