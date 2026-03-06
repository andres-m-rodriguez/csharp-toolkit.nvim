-- Solution management for .sln and .slnx files

local M = {}

local projects = require("csharp-toolkit.projects")

-- Create a new solution
function M.create_solution()
  local cwd = vim.fn.getcwd()

  vim.ui.input({
    prompt = "Solution name: ",
    default = vim.fn.fnamemodify(cwd, ":t"),
  }, function(sln_name)
    if not sln_name or sln_name == "" then return end

    -- Validate solution name
    if not sln_name:match("^%a[%w_%.%-]*$") then
      vim.notify("Invalid solution name", vim.log.levels.ERROR)
      return
    end

    vim.ui.select({ ".slnx (new XML format)", ".sln (classic format)" }, {
      prompt = "Solution format:",
    }, function(format_choice)
      if not format_choice then return end

      local use_slnx = format_choice:match("slnx")
      local ext = use_slnx and "slnx" or "sln"

      vim.ui.input({
        prompt = "Solution directory: ",
        default = cwd,
      }, function(sln_dir)
        if not sln_dir or sln_dir == "" then return end

        -- Create directory if needed
        if vim.fn.isdirectory(sln_dir) == 0 then
          vim.fn.mkdir(sln_dir, "p")
        end

        local sln_path = sln_dir .. "/" .. sln_name .. "." .. ext

        if use_slnx then
          -- Create .slnx file manually (dotnet doesn't support it directly yet)
          local slnx_content = [[<?xml version="1.0" encoding="utf-8"?>
<Solution>
  <Folder Name="/Solution Items/">
  </Folder>
</Solution>
]]
          local file = io.open(sln_path, "w")
          if file then
            file:write(slnx_content)
            file:close()
            vim.notify("Created solution: " .. sln_path, vim.log.levels.INFO)
            vim.cmd("edit " .. vim.fn.fnameescape(sln_path))
          else
            vim.notify("Failed to create solution file", vim.log.levels.ERROR)
          end
        else
          -- Use dotnet CLI for .sln
          local cmd = string.format('cd /d "%s" && dotnet new sln -n "%s"', sln_dir, sln_name)

          vim.fn.jobstart(cmd, {
            on_exit = function(_, exit_code)
              vim.schedule(function()
                if exit_code == 0 then
                  vim.notify("Created solution: " .. sln_path, vim.log.levels.INFO)
                  vim.cmd("edit " .. vim.fn.fnameescape(sln_path))
                else
                  vim.notify("Failed to create solution", vim.log.levels.ERROR)
                end
              end)
            end,
          })
        end
      end)
    end)
  end)
end

-- Find all .csproj files in the solution directory
local function find_csproj_files(root_dir)
  local results = {}
  local handle = vim.loop.fs_scandir(root_dir)
  if not handle then return results end

  local function scan(dir)
    local h = vim.loop.fs_scandir(dir)
    if not h then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(h)
      if not name then break end

      local full_path = dir .. "/" .. name

      if type == "directory" and not name:match("^%.") and name ~= "bin" and name ~= "obj" and name ~= "node_modules" then
        scan(full_path)
      elseif type == "file" and name:match("%.csproj$") then
        table.insert(results, full_path)
      end
    end
  end

  scan(root_dir)
  return results
end

-- Get projects already in solution
local function get_projects_in_solution(sln_path)
  local cmd = string.format('dotnet sln "%s" list', sln_path)
  local output = vim.fn.system(cmd)
  local projects_in_sln = {}

  for line in output:gmatch("[^\r\n]+") do
    if line:match("%.csproj$") then
      -- Normalize path
      local normalized = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
      projects_in_sln[normalized] = true
    end
  end

  return projects_in_sln
end

-- Add a project to the solution
function M.add_project_to_solution()
  local sln = projects.find_solution()
  if not sln then
    vim.notify("No solution found. Create one first with :CSNewSolution", vim.log.levels.WARN)
    return
  end

  local sln_dir = vim.fn.fnamemodify(sln, ":h")
  local csproj_files = find_csproj_files(sln_dir)

  if #csproj_files == 0 then
    vim.notify("No .csproj files found", vim.log.levels.WARN)
    return
  end

  -- Filter out projects already in solution
  local projects_in_sln = get_projects_in_solution(sln)
  local available = {}

  for _, csproj in ipairs(csproj_files) do
    local rel_path = csproj:sub(#sln_dir + 2):gsub("\\", "/")
    if not projects_in_sln[rel_path] then
      table.insert(available, {
        path = csproj,
        rel = rel_path,
        name = vim.fn.fnamemodify(csproj, ":t:r"),
      })
    end
  end

  if #available == 0 then
    vim.notify("All projects are already in the solution", vim.log.levels.INFO)
    return
  end

  -- Build picker items
  local items = {}
  for _, proj in ipairs(available) do
    table.insert(items, proj.name .. " (" .. proj.rel .. ")")
  end

  vim.ui.select(items, {
    prompt = "Select project to add:",
  }, function(choice, idx)
    if not choice or not idx then return end

    local proj = available[idx]
    projects.add_project_to_solution_file(sln, proj.path)
  end)
end

-- Remove a project from the solution
function M.remove_project_from_solution()
  local sln = projects.find_solution()
  if not sln then
    vim.notify("No solution found", vim.log.levels.WARN)
    return
  end

  -- Get projects in solution
  local cmd = string.format('dotnet sln "%s" list', sln)
  local output = vim.fn.system(cmd)
  local solution_projects = {}

  for line in output:gmatch("[^\r\n]+") do
    if line:match("%.csproj$") then
      local normalized = line:gsub("^%s+", ""):gsub("%s+$", "")
      table.insert(solution_projects, normalized)
    end
  end

  if #solution_projects == 0 then
    vim.notify("No projects in solution", vim.log.levels.INFO)
    return
  end

  vim.ui.select(solution_projects, {
    prompt = "Select project to remove:",
  }, function(choice)
    if not choice then return end

    local sln_dir = vim.fn.fnamemodify(sln, ":h")
    local project_path = sln_dir .. "/" .. choice

    local remove_cmd = string.format('dotnet sln "%s" remove "%s"', sln, project_path)

    vim.fn.jobstart(remove_cmd, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if exit_code == 0 then
            vim.notify("Removed from solution: " .. choice, vim.log.levels.INFO)
          else
            vim.notify("Failed to remove project", vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

-- List all projects in the solution
function M.list_projects()
  local sln = projects.find_solution()
  if not sln then
    vim.notify("No solution found", vim.log.levels.WARN)
    return
  end

  local cmd = string.format('dotnet sln "%s" list', sln)
  local output = vim.fn.system(cmd)

  -- Parse and display
  local lines = { "Projects in " .. vim.fn.fnamemodify(sln, ":t") .. ":", "" }

  for line in output:gmatch("[^\r\n]+") do
    if line:match("%.csproj$") then
      local name = vim.fn.fnamemodify(line, ":t:r")
      table.insert(lines, "  " .. name)
    end
  end

  if #lines == 2 then
    table.insert(lines, "  (no projects)")
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
