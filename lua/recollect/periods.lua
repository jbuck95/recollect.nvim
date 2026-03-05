-- ~/.config/nvim/lua/recollect/periods.lua
local M = {}
local config = require("recollect.config")

M.buf = nil
M.win = nil
M.ns = vim.api.nvim_create_namespace("recollect_periods")
M.periods = {}
M.selected_period = 1
M.on_close_callback = nil

local function get_config_path()
  local cfg = config.get()
  local dir = cfg.data_dir or vim.fn.stdpath("config")
  vim.fn.mkdir(dir, "p")
  return dir .. "/recollect.json"
end

function M.load_periods()
  local path = get_config_path()
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    local success, decoded = pcall(vim.fn.json_decode, content)
    if success and type(decoded) == "table" then
      M.periods = decoded
    else
      M.periods = config.get().periods
    end
  else
    M.periods = config.get().periods
  end
  config.current.periods = M.periods
end

function M.save_periods()
  local path = get_config_path()
  local parent = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(parent) == 0 then
    vim.fn.mkdir(parent, "p")
  end

  local file = io.open(path, "w")
  if file then
    file:write(vim.fn.json_encode(M.periods))
    file:close()
    config.current.periods = M.periods
  end
end

local function render_main()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)

  local lines = {
    "               ╔═══════════════════════════════════════╗",
    "               ║        		MANAGE PERIODS 	            ║",
    "               ╚═══════════════════════════════════════╝",
    "",
  }

  if #M.periods == 0 then
    table.insert(lines, "  No periods defined. Press 'a' to add one.")
  else
    for i, period in ipairs(M.periods) do
      local line = string.format("%s %d. %s (%s - %s) [%s]",
        i == M.selected_period and "->" or "  ",
        i,
        period.label or "N/A",
        period.start or "N/A",
        period.finish or "N/A",
        period.color or "N/A"
      )
      table.insert(lines, line)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  j/k: navigate | a: add | e/<CR>: edit | d: delete | q: close & save")

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

local function open_edit_window(period_index)
  local period = M.periods[period_index]

  local function prompt_for_field(field_name, current_value, callback)
    vim.ui.input({
      prompt = string.format("Enter %s for period '%s': ", field_name, period.label),
      default = current_value,
    }, function(input)
      if input ~= nil then
        period[field_name] = input
      end
      callback()
    end)
  end

  prompt_for_field("label", period.label, function()
    prompt_for_field("start", period.start, function()
      prompt_for_field("finish", period.finish, function()
        prompt_for_field("color", period.color, function()
          M.save_periods()
          render_main()
        end)
      end)
    end)
  end)
end

local function add_period()
  local new_period = {
    label = "New Period",
    start = os.date("%Y-%m-%d"),
    finish = "present",
    color = "blue",
  }
  table.insert(M.periods, new_period)
  M.selected_period = #M.periods
  M.save_periods()
  render_main()
  open_edit_window(M.selected_period)
end

local function edit_period()
  if M.selected_period > 0 and M.selected_period <= #M.periods then
    open_edit_window(M.selected_period)
  end
end

local function delete_period()
  if M.selected_period <= 0 or M.selected_period > #M.periods then return end
  local period = M.periods[M.selected_period]

  if vim.ui and vim.ui.confirm and type(vim.ui.confirm) == 'function' then
    vim.ui.confirm("Delete period '" .. period.label .. "'?", function(confirmed)
      if confirmed then
        table.remove(M.periods, M.selected_period)
        if M.selected_period > #M.periods and #M.periods > 0 then
          M.selected_period = #M.periods
        elseif #M.periods == 0 then
          M.selected_period = 0
        end
        M.save_periods()
        render_main()
      end
    end)
  else
    local response = vim.fn.input("Delete period '" .. period.label .. "'? (y/N): ")
    if response:lower() == 'y' then
      table.remove(M.periods, M.selected_period)
      if M.selected_period > #M.periods and #M.periods > 0 then
        M.selected_period = #M.periods
      elseif #M.periods == 0 then
        M.selected_period = 0
      end
      M.save_periods()
      render_main()
    end
  end
end

local function setup_main_keymaps()
  local buf = M.buf

  -- <Plug> definitions: noremap, buffer-local
  local popts = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set("n", "<Plug>(recollect-periods-quit)", function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, true)
      if M.on_close_callback then
        M.on_close_callback()
      end
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-periods-next)", function()
    if M.selected_period < #M.periods then
      M.selected_period = M.selected_period + 1
      render_main()
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-periods-prev)", function()
    if M.selected_period > 1 then
      M.selected_period = M.selected_period - 1
      render_main()
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-periods-add)",    add_period,    popts)
  vim.keymap.set("n", "<Plug>(recollect-periods-edit)",   edit_period,   popts)
  vim.keymap.set("n", "<Plug>(recollect-periods-delete)", delete_period, popts)

  -- Default key → <Plug> bindings
  local opts = { buffer = buf, remap = true, nowait = true, silent = true }

  vim.keymap.set("n", "q",    "<Plug>(recollect-periods-quit)",   opts)
  vim.keymap.set("n", "j",    "<Plug>(recollect-periods-next)",   opts)
  vim.keymap.set("n", "k",    "<Plug>(recollect-periods-prev)",   opts)
  vim.keymap.set("n", "a",    "<Plug>(recollect-periods-add)",    opts)
  vim.keymap.set("n", "e",    "<Plug>(recollect-periods-edit)",   opts)
  vim.keymap.set("n", "<CR>", "<Plug>(recollect-periods-edit)",   opts)
  vim.keymap.set("n", "d",    "<Plug>(recollect-periods-delete)", opts)
end

function M.open(opts)
  opts = opts or {}
  M.on_close_callback = opts.on_close

  M.load_periods()

  M.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf, "bufhidden", "wipe")

  local width = 70
  local height = 20

  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  render_main()
  setup_main_keymaps()
end

return M
