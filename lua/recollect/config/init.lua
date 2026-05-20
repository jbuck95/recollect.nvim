local M = {}

---@type recollect.ConfigDefaults
local defaults = require("recollect.config.defaults")

---@type recollect.Config
M.current = vim.deepcopy(defaults)

---Validate user config and return error message, or nil if valid.
---@param opts table
---@return string|nil
local function validate(opts)
  local ok, err = pcall(vim.validate, {
    birthday         = { opts.birthday, "string", true },
    max_age          = { opts.max_age, "number", true },
    grid_mode        = { opts.grid_mode, "string", true },
    locale           = { opts.locale, "string", true },
    note_split_mode  = { opts.note_split_mode, "string", true },
    daily_notes_path = { opts.daily_notes_path, "string", true },
    bar_position     = { opts.bar_position, "string", true },
    periods          = { opts.periods, "table", true },
    tag_symbols      = { opts.tag_symbols, "table", true },
    colors           = { opts.colors, "table", true },
    note_template    = { opts.note_template, "function", true },
  })
  if not ok then return err end
end

---Set and merge user configuration.
---@param opts? table
function M.set(opts)
  if opts == nil then return end
  local err = validate(opts)
  if err then
    vim.notify("recollect: invalid config: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  M.current = vim.tbl_deep_extend("force", M.current, opts)
end

---Get the current merged configuration.
---@return recollect.Config
function M.get()
  return M.current
end

return M
