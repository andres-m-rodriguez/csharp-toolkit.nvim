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

-- Find all .csproj files in a directory recursively
function M.find_csproj_files(root_dir)
  local results = {}

  local function scan(dir)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
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

-- Find .csproj directory and name starting from a directory
function M.find_csproj_info(start_dir)
  local current = start_dir

  while current ~= "" and current ~= "/" and not current:match("^%a:[\\/]?$") do
    local csproj = vim.fn.glob(current .. "/*.csproj")
    if csproj ~= "" then
      return current, vim.fn.fnamemodify(csproj, ":t:r")
    end
    current = vim.fn.fnamemodify(current, ":h")
  end

  return nil, nil
end

-- Find the nearest .csproj to the current file
function M.find_current_project()
  local current_file = vim.fn.expand("%:p")
  local current_dir = vim.fn.expand("%:p:h")

  while current_dir ~= "" and current_dir ~= "/" and not current_dir:match("^%a:[\\/]?$") do
    local csproj = vim.fn.glob(current_dir .. "/*.csproj")
    if csproj ~= "" then
      return vim.fn.fnamemodify(csproj, ":p")
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end

  return nil
end

-- Get existing references for a project
function M.get_project_references(csproj_path)
  local cmd = string.format('dotnet list "%s" reference', csproj_path)
  local output = vim.fn.system(cmd)
  local references = {}

  for line in output:gmatch("[^\r\n]+") do
    if line:match("%.csproj$") then
      local normalized = line:gsub("^%s+", ""):gsub("%s+$", "")
      table.insert(references, normalized)
    end
  end

  return references
end

-- Add a reference from one project to another
function M.add_reference()
  local sln_dir = M.get_solution_dir()
  local current_project = M.find_current_project()

  -- Find all projects
  local all_projects = M.find_csproj_files(sln_dir)

  if #all_projects == 0 then
    vim.notify("No projects found", vim.log.levels.WARN)
    return
  end

  -- Build source project list
  local source_items = {}
  local source_paths = {}
  for _, proj in ipairs(all_projects) do
    local name = vim.fn.fnamemodify(proj, ":t:r")
    local rel = proj:sub(#sln_dir + 2)
    table.insert(source_items, name .. " (" .. rel .. ")")
    table.insert(source_paths, proj)
  end

  -- Pre-select current project if found
  local default_idx = nil
  if current_project then
    for i, path in ipairs(source_paths) do
      if path == current_project then
        default_idx = i
        break
      end
    end
  end

  vim.ui.select(source_items, {
    prompt = "Select source project (the one that needs the reference):",
  }, function(choice, src_idx)
    if not choice or not src_idx then return end

    local source_project = source_paths[src_idx]
    local source_name = vim.fn.fnamemodify(source_project, ":t:r")

    -- Get existing references to filter them out
    local existing_refs = M.get_project_references(source_project)
    local existing_set = {}
    for _, ref in ipairs(existing_refs) do
      local ref_name = vim.fn.fnamemodify(ref, ":t:r")
      existing_set[ref_name] = true
    end

    -- Build target project list (excluding source and existing refs)
    local target_items = {}
    local target_paths = {}
    for i, proj in ipairs(all_projects) do
      if i ~= src_idx then
        local name = vim.fn.fnamemodify(proj, ":t:r")
        if not existing_set[name] then
          local rel = proj:sub(#sln_dir + 2)
          table.insert(target_items, name .. " (" .. rel .. ")")
          table.insert(target_paths, proj)
        end
      end
    end

    if #target_items == 0 then
      vim.notify("No available projects to reference", vim.log.levels.INFO)
      return
    end

    vim.ui.select(target_items, {
      prompt = "Select project to reference:",
    }, function(target_choice, target_idx)
      if not target_choice or not target_idx then return end

      local target_project = target_paths[target_idx]
      local target_name = vim.fn.fnamemodify(target_project, ":t:r")

      local cmd = string.format('dotnet add "%s" reference "%s"', source_project, target_project)

      vim.fn.jobstart(cmd, {
        on_exit = function(_, exit_code)
          vim.schedule(function()
            if exit_code == 0 then
              vim.notify(string.format("Added reference: %s -> %s", source_name, target_name), vim.log.levels.INFO)
            else
              vim.notify("Failed to add reference", vim.log.levels.ERROR)
            end
          end)
        end,
      })
    end)
  end)
end

-- Remove a reference from a project
function M.remove_reference()
  local sln_dir = M.get_solution_dir()
  local current_project = M.find_current_project()

  local all_projects = M.find_csproj_files(sln_dir)

  if #all_projects == 0 then
    vim.notify("No projects found", vim.log.levels.WARN)
    return
  end

  -- Build source project list
  local source_items = {}
  local source_paths = {}
  for _, proj in ipairs(all_projects) do
    local name = vim.fn.fnamemodify(proj, ":t:r")
    local rel = proj:sub(#sln_dir + 2)
    table.insert(source_items, name .. " (" .. rel .. ")")
    table.insert(source_paths, proj)
  end

  vim.ui.select(source_items, {
    prompt = "Select project to remove reference from:",
  }, function(choice, src_idx)
    if not choice or not src_idx then return end

    local source_project = source_paths[src_idx]
    local source_name = vim.fn.fnamemodify(source_project, ":t:r")

    -- Get existing references
    local existing_refs = M.get_project_references(source_project)

    if #existing_refs == 0 then
      vim.notify("No references in this project", vim.log.levels.INFO)
      return
    end

    -- Build reference list
    local ref_items = {}
    for _, ref in ipairs(existing_refs) do
      local name = vim.fn.fnamemodify(ref, ":t:r")
      table.insert(ref_items, name)
    end

    vim.ui.select(ref_items, {
      prompt = "Select reference to remove:",
    }, function(ref_choice, ref_idx)
      if not ref_choice or not ref_idx then return end

      local ref_path = existing_refs[ref_idx]
      local ref_name = vim.fn.fnamemodify(ref_path, ":t:r")

      local cmd = string.format('dotnet remove "%s" reference "%s"', source_project, ref_path)

      vim.fn.jobstart(cmd, {
        on_exit = function(_, exit_code)
          vim.schedule(function()
            if exit_code == 0 then
              vim.notify(string.format("Removed reference: %s -> %s", source_name, ref_name), vim.log.levels.INFO)
            else
              vim.notify("Failed to remove reference", vim.log.levels.ERROR)
            end
          end)
        end,
      })
    end)
  end)
end

-- List references for a project
function M.list_references()
  local sln_dir = M.get_solution_dir()
  local current_project = M.find_current_project()

  local all_projects = M.find_csproj_files(sln_dir)

  if #all_projects == 0 then
    vim.notify("No projects found", vim.log.levels.WARN)
    return
  end

  -- Build project list
  local items = {}
  local paths = {}
  for _, proj in ipairs(all_projects) do
    local name = vim.fn.fnamemodify(proj, ":t:r")
    local rel = proj:sub(#sln_dir + 2)
    table.insert(items, name .. " (" .. rel .. ")")
    table.insert(paths, proj)
  end

  vim.ui.select(items, {
    prompt = "Select project to list references:",
  }, function(choice, idx)
    if not choice or not idx then return end

    local project = paths[idx]
    local project_name = vim.fn.fnamemodify(project, ":t:r")

    local refs = M.get_project_references(project)

    local lines = { "References in " .. project_name .. ":", "" }

    if #refs == 0 then
      table.insert(lines, "  (no references)")
    else
      for _, ref in ipairs(refs) do
        local name = vim.fn.fnamemodify(ref, ":t:r")
        table.insert(lines, "  -> " .. name)
      end
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

-- Initialize a C# file with namespace and class
function M.init_file()
  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t:r")
  local dir = vim.fn.expand("%:p:h")

  -- Check if it's a .cs file
  if not filepath:match("%.cs$") then
    vim.notify("Not a C# file", vim.log.levels.WARN)
    return
  end

  -- Check if file is empty or only whitespace
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local has_content = false
  for _, line in ipairs(lines) do
    if line:match("%S") then
      has_content = true
      break
    end
  end

  if has_content then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "File is not empty. Replace contents?",
    }, function(choice)
      if choice == "Yes" then
        M._insert_template(filepath, filename, dir)
      end
    end)
  else
    M._insert_template(filepath, filename, dir)
  end
end

-- Internal: Insert the C# template
function M._insert_template(filepath, filename, dir)
  local project_dir, project_name = M.find_csproj_info(dir)
  local namespace

  if project_dir and project_name then
    -- Build namespace from project name + relative path
    local rel_path = dir:sub(#project_dir + 2)
    rel_path = rel_path:gsub("[\\/]", ".")
    if rel_path ~= "" then
      namespace = project_name .. "." .. rel_path
    else
      namespace = project_name
    end
  else
    -- Fallback: use parent directory name
    namespace = vim.fn.expand("%:p:h:t")
  end

  -- Clean up namespace
  namespace = namespace:gsub("[^%w%.]", "")

  local template = string.format([[namespace %s;

public class %s
{

}]], namespace, filename)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "\n"))
  -- Position cursor inside the class
  vim.api.nvim_win_set_cursor(0, { 5, 4 })
  vim.notify("Initialized: " .. filename .. ".cs", vim.log.levels.INFO)
end

return M
