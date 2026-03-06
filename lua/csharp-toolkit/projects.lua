-- Project management for C# projects

local M = {}

-- Find the nearest solution file
function M.find_solution()
  local cwd = vim.fn.getcwd()
  local current = cwd

  while current ~= "" and current ~= "/" and not current:match("^%a:[\\/]?$") do
    -- Check for .slnx first (new format), then .sln
    local slnx = vim.fn.glob(current .. "/*.slnx")
    if slnx ~= "" then
      return vim.fn.fnamemodify(slnx, ":p")
    end

    local sln = vim.fn.glob(current .. "/*.sln")
    if sln ~= "" then
      return vim.fn.fnamemodify(sln, ":p")
    end

    current = vim.fn.fnamemodify(current, ":h")
  end

  return nil
end

-- Get the solution directory
function M.get_solution_dir()
  local sln = M.find_solution()
  if sln then
    return vim.fn.fnamemodify(sln, ":h")
  end
  return vim.fn.getcwd()
end

-- Create a new project
function M.create_project(templates)
  local sln_dir = M.get_solution_dir()

  -- Build picker items
  local items = {}
  for i, tmpl in ipairs(templates) do
    table.insert(items, string.format("%d. %s %s", i, tmpl.icon or "", tmpl.name))
  end

  vim.ui.select(items, {
    prompt = "Select project type:",
  }, function(choice, idx)
    if not choice or not idx then return end

    local template = templates[idx]

    vim.ui.input({
      prompt = "Project name: ",
    }, function(project_name)
      if not project_name or project_name == "" then return end

      -- Validate project name
      if not project_name:match("^%a[%w_%.%-]*$") then
        vim.notify("Invalid project name. Use letters, numbers, dots, hyphens, underscores.", vim.log.levels.ERROR)
        return
      end

      vim.ui.input({
        prompt = "Project folder (relative to solution, empty for same name): ",
        default = project_name,
      }, function(folder)
        if folder == nil then return end
        if folder == "" then folder = project_name end

        local project_dir = sln_dir .. "/" .. folder
        local project_path = project_dir .. "/" .. project_name .. ".csproj"

        -- Create project
        local cmd = string.format(
          'dotnet new %s -n "%s" -o "%s"',
          template.template,
          project_name,
          project_dir
        )

        vim.notify("Creating project: " .. project_name, vim.log.levels.INFO)

        vim.fn.jobstart(cmd, {
          on_exit = function(_, exit_code)
            if exit_code == 0 then
              vim.schedule(function()
                vim.notify("Project created: " .. project_name, vim.log.levels.INFO)

                -- Ask if user wants to add to solution
                local sln = M.find_solution()
                if sln then
                  vim.ui.select({ "Yes", "No" }, {
                    prompt = "Add to solution?",
                  }, function(add_choice)
                    if add_choice == "Yes" then
                      M.add_project_to_solution_file(sln, project_path)
                    end
                  end)
                end
              end)
            else
              vim.schedule(function()
                vim.notify("Failed to create project. Check dotnet CLI.", vim.log.levels.ERROR)
              end)
            end
          end,
          on_stderr = function(_, data)
            if data and data[1] ~= "" then
              vim.schedule(function()
                for _, line in ipairs(data) do
                  if line ~= "" then
                    vim.notify(line, vim.log.levels.WARN)
                  end
                end
              end)
            end
          end,
        })
      end)
    end)
  end)
end

-- Add a project to a solution file
function M.add_project_to_solution_file(sln_path, project_path)
  local cmd = string.format('dotnet sln "%s" add "%s"', sln_path, project_path)

  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          vim.notify("Added to solution", vim.log.levels.INFO)
        else
          vim.notify("Failed to add to solution", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

return M
