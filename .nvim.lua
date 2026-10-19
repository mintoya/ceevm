local M = {}
local namespace = vim.api.nvim_create_namespace('zig_inline')
local jobs = {}

-- ZLS does not include compiler reference traces in its diagnostics. Use the
-- compiler's trace to show errors from dependencies at project call sites.
function M.parse(output, root)
  root = vim.fs.normalize(root)
  local diagnostics = {}
  local current
  local in_trace = false
  local seen = {}
  local function project_path(path)
    if not vim.startswith(path, '/') then
      path = vim.fs.joinpath(root, path)
    end
    path = vim.fs.normalize(path)
    return path, vim.startswith(path, root .. '/')
  end
  for line in output:gmatch('[^\r\n]+') do
    local path, row, col, message = line:match('^(.-):(%d+):(%d+): error: (.*)$')
    if path then
      local _, local_error = project_path(path)
      current = not local_error and {
        message = message,
        origin = path .. ':' .. row .. ':' .. col,
      } or nil
      in_trace = false
    elseif line == 'referenced by:' then
      in_trace = true
    elseif current and in_trace then
      local ref, ref_row, ref_col = line:match('^    .-: (.-):(%d+):(%d+)$')
      if ref then
        local full_path, in_project = project_path(ref)
        if in_project then
          local key = full_path .. ':' .. ref_row .. ':' .. ref_col .. ':' .. current.message
          if not seen[key] then
            seen[key] = true
            diagnostics[full_path] = diagnostics[full_path] or {}
            table.insert(diagnostics[full_path], {
              lnum = tonumber(ref_row) - 1,
              col = tonumber(ref_col) - 1,
              severity = vim.diagnostic.severity.ERROR,
              source = 'zig check',
              message = current.message .. '\nFrom ' .. current.origin,
            })
          end
        end
      else
        in_trace = false
      end
    end
  end
  return diagnostics
end

local function check(client)
  local root = client.config.root_dir
  if not root or not vim.uv.fs_stat(vim.fs.joinpath(root, 'build.zig')) then return end
  local state = jobs[root] or { generation = 0, buffers = {} }
  jobs[root] = state
  state.generation = state.generation + 1
  local generation = state.generation
  if state.process then
    state.process:kill(15)
    state.process = nil
  end
  vim.defer_fn(function()
    if generation ~= state.generation then return end
    local settings = (client.config.settings or {}).zls or {}
    local command = { settings.zig_exe_path or 'zig', 'build', 'check', '--color', 'off', '-freference-trace=32' }
    vim.list_extend(command, settings.build_on_save_args or {})
    state.process = vim.system(command, { cwd = root, text = true }, function(result)
      vim.schedule(function()
        if generation ~= state.generation then return end
        state.process = nil
        for buffer in pairs(state.buffers) do
          if vim.api.nvim_buf_is_valid(buffer) then
            vim.diagnostic.reset(namespace, buffer)
          end
        end
        state.buffers = {}
        for path, diagnostics in pairs(M.parse(result.stderr or '', root)) do
          local buffer = vim.fn.bufadd(path)
          vim.diagnostic.set(namespace, buffer, diagnostics)
          state.buffers[buffer] = true
        end
      end)
    end)
  end, 150)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ZigInlineDiagnostics', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client.name == 'zls' then check(client) end
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = { '*.zig', '*.zon' },
    callback = function(event)
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = event.buf, name = 'zls' })) do
        check(client)
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, state in pairs(jobs) do
        state.generation = state.generation + 1
        if state.process then state.process:kill(15) end
      end
    end,
  })
end

M.setup()
