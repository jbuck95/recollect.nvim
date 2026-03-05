-- ~/.config/nvim/lua/recollect/recurring.lua
local M = {}
local config = require("recollect.config")

M.buf = nil
M.win = nil
M.events = {}
M.selected = 1
M.on_close_callback = nil

local function get_store_path()
  local cfg = config.get()
  local dir = cfg.data_dir or vim.fn.stdpath("config")
  vim.fn.mkdir(dir, "p")
  return dir .. "/recollect_recurring.json"
end

function M.load()
  local path = get_store_path()
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok and type(decoded) == "table" then
      M.events = decoded
      return
    end
  end
  M.events = {}
end

function M.save()
  local path = get_store_path()
  local file = io.open(path, "w")
  if file then
    file:write(vim.fn.json_encode(M.events))
    file:close()
  end
end

-- Returns synthetic metadata if date_str matches any recurring event.
-- Merges all matching events into one metadata table.
function M.get_virtual_metadata(date_str)
  if #M.events == 0 then M.load() end
  local year, month, day = date_str:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if not year then return nil end

  local matched_tags = {}
  local matched_title = nil

  for _, ev in ipairs(M.events) do
    local matches = false
    if ev.recurrence == "monthly" then
      -- ev.date is "DD"
      matches = (day == ev.date)
    else
      -- default yearly: ev.date is "MM-DD"
      matches = (month .. "-" .. day == ev.date)
    end

    if matches then
      table.insert(matched_tags, ev.tag or "event")
      if not matched_title then
        matched_title = ev.title
      end
    end
  end

  if #matched_tags == 0 then return nil end

  return {
    tags  = matched_tags,
    title = matched_title,
    _recurring = true,
  }
end

-- Manager UI
local function render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)

  local lines = {
    "               ╔═══════════════════════════════════════╗",
    "               ║       RECURRING EVENTS                ║",
    "               ╚═══════════════════════════════════════╝",
    "",
  }

  if #M.events == 0 then
    table.insert(lines, "  No recurring events. Press 'a' to add one.")
  else
    for i, ev in ipairs(M.events) do
      local rec = ev.recurrence or "yearly"
      local line = string.format("%s %d. [%s] %s  |  %s  |  %s",
        i == M.selected and "->" or "  ",
        i,
        ev.tag or "event",
        ev.title or "Untitled",
        ev.date or "??",
        rec
      )
      table.insert(lines, line)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  j/k: navigate | a: add | e/<CR>: edit | d: delete | q: close")

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

local function edit_event(idx)
  local ev = M.events[idx]

  local function prompt(field, current, cb)
    vim.ui.input({
      prompt  = string.format("  %s [%s]: ", field, tostring(current or "")),
      default = tostring(current or ""),
    }, function(input)
      if input ~= nil then ev[field] = input end
      cb()
    end)
  end

  prompt("title", ev.title, function()
    prompt("tag", ev.tag, function()
      vim.ui.input({
        prompt  = "  date — yearly: MM-DD, monthly: DD [" .. (ev.date or "") .. "]: ",
        default = ev.date or "",
      }, function(input)
        if input ~= nil then ev.date = input end
        vim.ui.input({
          prompt  = "  recurrence (yearly/monthly) [" .. (ev.recurrence or "yearly") .. "]: ",
          default = ev.recurrence or "yearly",
        }, function(input)
          if input ~= nil then ev.recurrence = input end
          M.save()
          render()
        end)
      end)
    end)
  end)
end

local function add_event()
  table.insert(M.events, {
    title       = "New Event",
    tag         = "event",
    date        = os.date("%m-%d"),
    recurrence  = "yearly",
  })
  M.selected = #M.events
  M.save()
  render()
  edit_event(M.selected)
end

local function delete_event()
  if M.selected <= 0 or M.selected > #M.events then return end
  local ev = M.events[M.selected]
  local response = vim.fn.input("Delete '" .. (ev.title or "event") .. "'? (y/N): ")
  if response:lower() == "y" then
    table.remove(M.events, M.selected)
    M.selected = math.min(M.selected, #M.events)
    if #M.events == 0 then M.selected = 0 end
    M.save()
    render()
  end
end

local function setup_keymaps()
  local buf  = M.buf
  local popts = { buffer = buf, noremap = true, silent = true }
  local opts  = { buffer = buf, remap = true, nowait = true, silent = true }

  vim.keymap.set("n", "<Plug>(recollect-rec-quit)", function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, true)
      if M.on_close_callback then M.on_close_callback() end
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-rec-next)", function()
    if M.selected < #M.events then
      M.selected = M.selected + 1
      render()
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-rec-prev)", function()
    if M.selected > 1 then
      M.selected = M.selected - 1
      render()
    end
  end, popts)

  vim.keymap.set("n", "<Plug>(recollect-rec-add)",    add_event,                   popts)
  vim.keymap.set("n", "<Plug>(recollect-rec-edit)",   function() edit_event(M.selected) end, popts)
  vim.keymap.set("n", "<Plug>(recollect-rec-delete)", delete_event,                popts)

  vim.keymap.set("n", "q",    "<Plug>(recollect-rec-quit)",   opts)
  vim.keymap.set("n", "j",    "<Plug>(recollect-rec-next)",   opts)
  vim.keymap.set("n", "k",    "<Plug>(recollect-rec-prev)",   opts)
  vim.keymap.set("n", "a",    "<Plug>(recollect-rec-add)",    opts)
  vim.keymap.set("n", "e",    "<Plug>(recollect-rec-edit)",   opts)
  vim.keymap.set("n", "<CR>", "<Plug>(recollect-rec-edit)",   opts)
  vim.keymap.set("n", "d",    "<Plug>(recollect-rec-delete)", opts)
end

function M.open(opts)
  opts = opts or {}
  M.on_close_callback = opts.on_close
  M.load()

  M.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf, "bufhidden", "wipe")

  local width  = 72
  local height = 22

  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    col      = math.floor((vim.o.columns - width) / 2),
    row      = math.floor((vim.o.lines - height) / 2),
    style    = "minimal",
    border   = "rounded",
  })

  render()
  setup_keymaps()
end

return M
