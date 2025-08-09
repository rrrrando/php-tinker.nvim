local M = {}

M.run_tinker = function()
  vim.cmd('set ft=php_only')

  -- MARK: get contents and context
  local contents = vim.trim(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
  if (contents ~= "<?php") then
    contents = contents:finish(";")
  end
  local b64contents = vim.base64.encode(contents)
  local working_dir = vim.fn.getcwd()

  -- MARK: Get php version
  local getPhpVersion_Command = "php -v | grep \"PHP [0-9]\\.[0-9]\" | sed 's/^.* \\([0-9]\\.[0-9]\\).*$/\\1/'";
  local phpver_handle = io.popen(getPhpVersion_Command)
  local phpver_result = vim.trim(phpver_handle:read("*a"))
  phpver_handle:close()
  local versionValid = string.match(phpver_result, '/\\d\\.\\d/') ~= nil;

  local pluginDirectory = debug.getinfo(1).source:sub(2):beforeLast('/');

  -- MARK: run command
  local command = string.format(
    'php %s/client-%s.phar %s execute "%s"',
    pluginDirectory,
    phpver_result,
    working_dir,
    b64contents
  );
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()

  -- MARK: process/prettify results
  -- first we ensure a successful result
  if not vim.startswith(result, "TWEAKPHP_RESULT") then
    vim.notify(result, vim.log.levels.ERROR)
    do return end
  end

  -- then we parse the result
  local datastr = result:sub(("TWEAKPHP_RESULT:"):len() + 1)
  local data = vim.json.decode(datastr)

  local info_contents = ""

  for index, value in ipairs(data.output) do
    if vim.trim(info_contents) ~= "" then
      info_contents = info_contents .. "\n\n\n"
    end

    if value.output and value.output ~= "" then
      info_contents = info_contents .. " // LINE " .. value.line .. "\n\n" .. value.output
    end
  end


  local olddata = vim.g.dakin_php_playground

  -- MARK: create split buffer
  local workingWin = vim.api.nvim_get_current_win()
  olddata.state.workingWin = workingWin

  local win, buf
  -- restore existing window if possible
  if olddata.state.win == nil or not vim.api.nvim_win_is_valid(olddata.state.win) then
    vim.cmd('vsplit')
    win = vim.api.nvim_get_current_win()
    olddata.state.win = win
  else
    win = olddata.state.win
  end

  --restore existing buffer if possible
  if olddata.state.buf == nil or not vim.api.nvim_buf_is_valid(olddata.state.buf) then
    buf = vim.api.nvim_create_buf(true, true)
    olddata.state.buf = buf
  else
    buf = olddata.state.buf
  end

  vim.api.nvim_win_set_buf(win, buf)
  vim.cmd('set ft=php_only') -- add syntax highlighting

  -- switch back to editor window
  vim.api.nvim_set_current_win(workingWin)

  -- add <?php if not already present to keep line numbers consistent
  if not vim.startswith(contents, "<?php") then
    contents = "<?php\n" .. contents
    vim.api.nvim_buf_set_lines(0, 0, -1, false, contents:split("\n", true))
  end

  -- Placeholder results text
  if info_contents == "" then
    info_contents = "\n\n\n// Get started by entering some code into the left window"
  end
  -- send processed results to results buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, info_contents:split("\n", true))

  -- save state
  vim.g.dakin_php_playground = olddata
end

M.setup = function (opts)
  opts = opts or {}

  -- prepare state table
  vim.g.dakin_php_playground = { state = { buf = nil, win = nil, workingWin = nil } }

  -- easily bootable tinker window
  vim.api.nvim_create_user_command('PhpTinker', function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "<?php", "", "\"Tinker away!\"" }) -- example code
    vim.api.nvim_win_set_cursor(0, { 3, 0 })                                          -- position cursor

    vim.api.nvim_buf_create_user_command(buf, 'PhpTinkerRun', M.run_tinker, {})

    -- setup Refresh rePl keymap
    if opts.keymaps and opts.keymaps.run_tinker then
      vim.keymap.set('n', opts.keymaps.run_tinker, M.run_tinker, { buffer = true })
    end

    -- initialize results window by running once at startup
    M.run_tinker()
  end, {})
end

return M
