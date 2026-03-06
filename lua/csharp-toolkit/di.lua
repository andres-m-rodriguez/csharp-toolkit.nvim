-- Dependency Injection helpers for C#

local M = {}

-- LSP Symbol kinds we care about
local SYMBOL_KIND = {
  Class = 5,
  Interface = 11,
  Struct = 23,
}

-- Get workspace symbols from LSP
local function get_workspace_symbols(query, callback)
  local params = { query = query or "" }

  vim.lsp.buf_request(0, "workspace/symbol", params, function(err, result)
    if err then
      vim.notify("LSP error: " .. vim.inspect(err), vim.log.levels.ERROR)
      callback({})
      return
    end

    if not result then
      callback({})
      return
    end

    -- Filter for classes and interfaces
    local symbols = {}
    for _, symbol in ipairs(result) do
      if symbol.kind == SYMBOL_KIND.Class or
         symbol.kind == SYMBOL_KIND.Interface or
         symbol.kind == SYMBOL_KIND.Struct then
        table.insert(symbols, {
          name = symbol.name,
          kind = symbol.kind,
          location = symbol.location,
          containerName = symbol.containerName,
        })
      end
    end

    callback(symbols)
  end)
end

-- Find the class in the current buffer
local function find_class_info()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  for i, line in ipairs(lines) do
    -- Match class declaration
    local class_name = line:match("^%s*public%s+class%s+(%w+)")
      or line:match("^%s*internal%s+class%s+(%w+)")
      or line:match("^%s*public%s+partial%s+class%s+(%w+)")
      or line:match("^%s*public%s+sealed%s+class%s+(%w+)")

    if class_name then
      return {
        name = class_name,
        line = i,
        indent = line:match("^(%s*)") or "",
      }
    end
  end

  return nil
end

-- Find existing constructor
local function find_constructor(class_name)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  for i, line in ipairs(lines) do
    -- Match constructor: public ClassName(
    if line:match("public%s+" .. class_name .. "%s*%(") then
      -- Find the closing paren and opening brace
      local start_line = i
      local end_line = i
      local brace_line = nil

      -- Check if constructor spans multiple lines
      local full_sig = line
      local j = i
      while not full_sig:match("%)") and j < #lines do
        j = j + 1
        full_sig = full_sig .. "\n" .. lines[j]
        end_line = j
      end

      -- Find opening brace
      for k = end_line, math.min(end_line + 2, #lines) do
        if lines[k]:match("{") then
          brace_line = k
          break
        end
      end

      return {
        start_line = start_line,
        end_line = end_line,
        brace_line = brace_line,
        signature = full_sig,
      }
    end
  end

  return nil
end

-- Find existing fields
local function find_existing_fields()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fields = {}

  for i, line in ipairs(lines) do
    -- Match: private readonly IService _service;
    local field_type, field_name = line:match("private%s+readonly%s+(%w+)%s+(_?%w+)%s*;")
    if field_type and field_name then
      fields[field_type] = {
        name = field_name,
        line = i,
      }
    end
  end

  return fields
end

-- Generate field name from type (ILogger -> _logger)
local function type_to_field_name(type_name)
  local name = type_name
  -- Remove I prefix for interfaces
  if name:match("^I[A-Z]") then
    name = name:sub(2)
  end
  -- Convert to camelCase and add underscore prefix
  name = "_" .. name:sub(1, 1):lower() .. name:sub(2)
  return name
end

-- Generate parameter name from type (ILogger -> logger)
local function type_to_param_name(type_name)
  local name = type_name
  -- Remove I prefix for interfaces
  if name:match("^I[A-Z]") then
    name = name:sub(2)
  end
  -- Convert to camelCase
  name = name:sub(1, 1):lower() .. name:sub(2)
  return name
end

-- Add services using Telescope (with LSP completions)
function M.add_service()
  local class_info = find_class_info()
  if not class_info then
    vim.notify("No class found in current file", vim.log.levels.WARN)
    return
  end

  -- Check if Telescope is available
  local has_telescope, telescope = pcall(require, "telescope.builtin")

  if has_telescope then
    M._add_service_telescope(class_info)
  else
    M._add_service_input(class_info)
  end
end

-- Add service using Telescope with LSP symbols
function M._add_service_telescope(class_info)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local selected_services = {}

  -- First, let's get document symbols from current buffer and workspace
  local function collect_symbols(callback)
    local all_symbols = {}

    -- Get workspace symbols with a broad query
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if #clients == 0 then
      vim.notify("No LSP client attached", vim.log.levels.WARN)
      callback({})
      return
    end

    -- Try workspace symbols first
    vim.lsp.buf_request(0, "workspace/symbol", { query = "" }, function(err, result)
      if result then
        for _, symbol in ipairs(result) do
          if symbol.kind == SYMBOL_KIND.Class or
             symbol.kind == SYMBOL_KIND.Interface or
             symbol.kind == SYMBOL_KIND.Struct then
            local kind_name = symbol.kind == SYMBOL_KIND.Interface and "interface"
              or symbol.kind == SYMBOL_KIND.Struct and "struct"
              or "class"
            table.insert(all_symbols, {
              name = symbol.name,
              kind = kind_name,
              container = symbol.containerName or "",
            })
          end
        end
      end

      -- If we got symbols, use them; otherwise try a different approach
      if #all_symbols > 0 then
        callback(all_symbols)
      else
        -- Fallback: scan .cs files for class/interface declarations
        M._scan_project_for_types(function(scanned)
          callback(scanned)
        end)
      end
    end)
  end

  collect_symbols(function(symbols)
    if #symbols == 0 then
      vim.notify("No symbols found. Try typing the service name manually.", vim.log.levels.WARN)
      M._add_service_input(class_info)
      return
    end

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 40 },
        { width = 12 },
        { remaining = true },
      },
    })

    pickers.new({}, {
      prompt_title = "Add DI Service (<Tab> multi-select, <CR> confirm)",
      finder = finders.new_table({
        results = symbols,
        entry_maker = function(entry)
          return {
            value = entry,
            display = function(e)
              return displayer({
                e.value.name,
                { e.value.kind, "Comment" },
                { e.value.container, "Comment" },
              })
            end,
            ordinal = entry.name .. " " .. entry.container,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        -- Multi-select with Tab
        map("i", "<Tab>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local already_selected = false
            for i, s in ipairs(selected_services) do
              if s.name == entry.value.name then
                table.remove(selected_services, i)
                already_selected = true
                vim.notify("Removed: " .. entry.value.name, vim.log.levels.INFO)
                break
              end
            end
            if not already_selected then
              table.insert(selected_services, entry.value)
              vim.notify("Selected: " .. entry.value.name .. " (" .. #selected_services .. " total)", vim.log.levels.INFO)
            end
          end
          actions.move_selection_next(prompt_bufnr)
        end)

        map("n", "<Tab>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local already_selected = false
            for i, s in ipairs(selected_services) do
              if s.name == entry.value.name then
                table.remove(selected_services, i)
                already_selected = true
                break
              end
            end
            if not already_selected then
              table.insert(selected_services, entry.value)
            end
          end
          actions.move_selection_next(prompt_bufnr)
        end)

        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if entry then
            local exists = false
            for _, s in ipairs(selected_services) do
              if s.name == entry.value.name then
                exists = true
                break
              end
            end
            if not exists then
              table.insert(selected_services, entry.value)
            end
          end

          if #selected_services > 0 then
            M._inject_services(class_info, selected_services)
          else
            vim.notify("No services selected", vim.log.levels.WARN)
          end
        end)

        return true
      end,
    }):find()
  end)
end

-- Fallback: Scan project files for class/interface definitions
function M._scan_project_for_types(callback)
  local symbols = {}
  local projects = require("csharp-toolkit.projects")
  local sln_dir = projects.get_solution_dir()

  -- Find all .cs files
  local cs_files = {}
  local function scan_dir(dir)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      local full_path = dir .. "/" .. name

      if type == "directory" and not name:match("^%.") and name ~= "bin" and name ~= "obj" and name ~= "node_modules" then
        scan_dir(full_path)
      elseif type == "file" and name:match("%.cs$") then
        table.insert(cs_files, full_path)
      end
    end
  end

  scan_dir(sln_dir)

  -- Parse each file for class/interface declarations
  for _, file in ipairs(cs_files) do
    local f = io.open(file, "r")
    if f then
      local content = f:read("*all")
      f:close()

      -- Match interface declarations
      for name in content:gmatch("interface%s+([%w_]+)") do
        table.insert(symbols, { name = name, kind = "interface", container = "" })
      end

      -- Match class declarations
      for name in content:gmatch("class%s+([%w_]+)") do
        table.insert(symbols, { name = name, kind = "class", container = "" })
      end
    end
  end

  -- Remove duplicates
  local seen = {}
  local unique = {}
  for _, sym in ipairs(symbols) do
    if not seen[sym.name] then
      seen[sym.name] = true
      table.insert(unique, sym)
    end
  end

  callback(unique)
end

-- Fallback: Add service using vim.ui.input
function M._add_service_input(class_info)
  vim.ui.input({
    prompt = "Service type (e.g., ILogger, IHttpClientFactory): ",
  }, function(input)
    if not input or input == "" then return end

    local services = {}
    -- Support comma-separated input
    for service in input:gmatch("[^,]+") do
      service = service:match("^%s*(.-)%s*$") -- trim
      if service ~= "" then
        table.insert(services, { name = service, kind = "interface" })
      end
    end

    if #services > 0 then
      M._inject_services(class_info, services)
    end
  end)
end

-- Inject services into the class
function M._inject_services(class_info, services)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_fields = find_existing_fields()
  local constructor = find_constructor(class_info.name)

  -- Filter out services that already exist
  local new_services = {}
  for _, service in ipairs(services) do
    if not existing_fields[service.name] then
      table.insert(new_services, service)
    else
      vim.notify("Service already exists: " .. service.name, vim.log.levels.INFO)
    end
  end

  if #new_services == 0 then
    vim.notify("All services already exist", vim.log.levels.INFO)
    return
  end

  -- Find where to insert fields (after class declaration, before any methods)
  local field_insert_line = class_info.line

  -- Look for existing fields or first method
  for i = class_info.line + 1, #lines do
    local line = lines[i]
    if line:match("^%s*private%s+readonly") then
      field_insert_line = i
    elseif line:match("^%s*public%s+%w+%s*%(") or line:match("^%s*private%s+%w+%s*%(") then
      break
    elseif line:match("^%s*}%s*$") then
      break
    end
  end

  local base_indent = "    "
  local edits = {}

  -- Generate field declarations
  local field_lines = {}
  for _, service in ipairs(new_services) do
    local field_name = type_to_field_name(service.name)
    table.insert(field_lines, base_indent .. "private readonly " .. service.name .. " " .. field_name .. ";")
  end

  if constructor then
    -- Update existing constructor
    -- Parse existing parameters
    local existing_params = {}
    local param_match = constructor.signature:match("%((.-)%)")
    if param_match and param_match ~= "" then
      for param in param_match:gmatch("([^,]+)") do
        param = param:match("^%s*(.-)%s*$")
        table.insert(existing_params, param)
      end
    end

    -- Add new parameters
    for _, service in ipairs(new_services) do
      local param_name = type_to_param_name(service.name)
      table.insert(existing_params, service.name .. " " .. param_name)
    end

    -- Generate new constructor signature
    local new_sig = base_indent .. "public " .. class_info.name .. "("
    if #existing_params <= 2 then
      new_sig = new_sig .. table.concat(existing_params, ", ") .. ")"
    else
      new_sig = new_sig .. "\n"
      for i, param in ipairs(existing_params) do
        new_sig = new_sig .. base_indent .. base_indent .. param
        if i < #existing_params then
          new_sig = new_sig .. ","
        end
        new_sig = new_sig .. "\n"
      end
      new_sig = new_sig .. base_indent .. ")"
    end

    -- Generate assignment lines
    local assign_lines = {}
    for _, service in ipairs(new_services) do
      local field_name = type_to_field_name(service.name)
      local param_name = type_to_param_name(service.name)
      table.insert(assign_lines, base_indent .. base_indent .. field_name .. " = " .. param_name .. ";")
    end

    -- Apply edits
    -- 1. Insert fields after last field or class declaration
    local field_text = table.concat(field_lines, "\n")
    vim.api.nvim_buf_set_lines(0, field_insert_line, field_insert_line, false, field_lines)

    -- Adjust line numbers for constructor (fields were inserted above)
    local offset = #field_lines
    local ctor_start = constructor.start_line + offset - 1
    local ctor_end = constructor.end_line + offset
    local brace_line = constructor.brace_line + offset

    -- 2. Replace constructor signature
    local new_sig_lines = vim.split(new_sig, "\n")
    vim.api.nvim_buf_set_lines(0, ctor_start, ctor_end, false, new_sig_lines)

    -- 3. Insert assignments after opening brace
    local new_brace_line = ctor_start + #new_sig_lines
    -- Find the line with opening brace
    local all_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i = ctor_start + 1, math.min(ctor_start + #new_sig_lines + 3, #all_lines) do
      if all_lines[i] and all_lines[i]:match("{") then
        vim.api.nvim_buf_set_lines(0, i, i, false, assign_lines)
        break
      end
    end

  else
    -- Create new constructor
    local params = {}
    local assigns = {}

    for _, service in ipairs(new_services) do
      local field_name = type_to_field_name(service.name)
      local param_name = type_to_param_name(service.name)
      table.insert(params, service.name .. " " .. param_name)
      table.insert(assigns, base_indent .. base_indent .. field_name .. " = " .. param_name .. ";")
    end

    local ctor_lines = { "" }

    -- Constructor signature
    if #params <= 2 then
      table.insert(ctor_lines, base_indent .. "public " .. class_info.name .. "(" .. table.concat(params, ", ") .. ")")
    else
      table.insert(ctor_lines, base_indent .. "public " .. class_info.name .. "(")
      for i, param in ipairs(params) do
        local line = base_indent .. base_indent .. param
        if i < #params then
          line = line .. ","
        else
          line = line .. ")"
        end
        table.insert(ctor_lines, line)
      end
    end

    table.insert(ctor_lines, base_indent .. "{")
    for _, assign in ipairs(assigns) do
      table.insert(ctor_lines, assign)
    end
    table.insert(ctor_lines, base_indent .. "}")

    -- Insert fields
    vim.api.nvim_buf_set_lines(0, field_insert_line, field_insert_line, false, field_lines)

    -- Insert constructor after fields
    local ctor_insert = field_insert_line + #field_lines
    vim.api.nvim_buf_set_lines(0, ctor_insert, ctor_insert, false, ctor_lines)
  end

  local names = {}
  for _, s in ipairs(new_services) do
    table.insert(names, s.name)
  end
  vim.notify("Added services: " .. table.concat(names, ", "), vim.log.levels.INFO)
end

return M
