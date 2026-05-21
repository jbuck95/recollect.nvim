---@class recollect.Health
local M = {}

---Health check for :checkhealth recollect
function M.check()
  vim.health.start("recollect.nvim")

  local ok, err = pcall(require, "recollect.config")
  if ok then
    vim.health.ok("recollect core loaded")
    local cfg = require("recollect.config").get()
    if type(cfg) == "table" then
      vim.health.ok("config initialised (grid_mode: " .. (cfg.grid_mode or "?") .. ")")
    else
      vim.health.error("config not a table after get()")
    end
  else
    vim.health.error("recollect failed to load: " .. tostring(err))
  end

  if pcall(require, "plenary") then
    vim.health.ok("plenary.nvim installed")
  else
    vim.health.error("plenary.nvim not installed (required for directory scanning)")
  end

  if pcall(require, "telescope") then
    vim.health.ok("telescope.nvim installed (optional: tag picker, content search)")
  else
    vim.health.warn("telescope.nvim not installed (tag picker and content search unavailable)")
  end

  local ok_cfg, mod_cfg = pcall(require, "recollect.config")
  local cfg = ok_cfg and type(mod_cfg.get) == "function" and mod_cfg.get() or {}

  local notes_path = (cfg.daily_notes_path or "~/Documents/notes/dailies/")
  if vim.fn.isdirectory(vim.fn.fnameescape(notes_path)) == 1 then
    vim.health.ok("daily_notes_path: " .. notes_path)
  else
    vim.health.warn("daily_notes_path does not exist: " .. notes_path)
  end

  local data_dir = cfg.data_dir or vim.fn.stdpath("config")
  if vim.fn.isdirectory(vim.fn.fnameescape(data_dir)) == 1 then
    vim.health.ok("data_dir: " .. data_dir)
  else
    vim.health.info("data_dir will be created on first use: " .. data_dir)
  end

  if type(cfg.note_template) == "function" then
    vim.health.ok("note_template is a function")
  else
    vim.health.error("note_template is not a function")
  end
end

return M
