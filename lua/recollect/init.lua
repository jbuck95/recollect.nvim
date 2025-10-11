-- ~/.config/nvim/lua/recollect/init.lua
local M = {}
local config = require("recollect.config")
local grid = require("recollect.grid")
local notes = require("recollect.notes")
local ui = require("recollect.ui")

M.config = config.defaults

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  config.set(M.config)
  vim.api.nvim_create_user_command("Recollect", M.open, {})
end

function M.open()
  ui.open()
end

function M.create_daily_note()
  notes.create_today()
end

function M.jump_to_date(date_str)
  notes.open_or_create(date_str)
end

return M
