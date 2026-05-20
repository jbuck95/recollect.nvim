---@mod recollect
---@brief Life-grid daily notes visualiser for Neovim

local M = {}

M.version = "0.0.1"

---@class recollect.Config
---@field birthday          string       Birth date (YYYY-MM-DD)
---@field data_dir          string?      Custom data directory for periods/recurring JSON
---@field max_age           number       Maximum age in years
---@field grid_mode         string       "life" | "year" | "calendar"
---@field locale            string       Locale for date formatting (e.g. "en_US.UTF-8")
---@field note_split_mode   string       "split" | "reuse"
---@field daily_notes_path  string       Path to daily notes directory
---@field daily_notes_format string      strftime pattern for note filenames
---@field note_template     fun(date_str: string): string  Template factory
---@field periods           table[]      Default period definitions
---@field bar_position      string       "top" | "bottom"
---@field bar_offset        number?      Additional row offset for status bar
---@field tag_symbols       table<string,string>  Tag -> unicode symbol map
---@field colors            table<string,string>  Highlight colour map
---@field tracked_tags      table<string,recollect.TagTracking>?  Telescope tag-picker config

---@class recollect.TagTracking
---@field label  string
---@field icon?  string
---@field order? number

--- Get the current merged configuration.
---@return recollect.Config
function M.get_config()
  return require("recollect.config").get()
end

--- Merge user options into the default configuration.
--- This is optional – the plugin works out of the box with defaults.
---@param opts? recollect.Config
function M.setup(opts)
  require("recollect.config").set(opts or {})
end

--- Open the life-grid UI in the current window.
function M.open()
  require("recollect.ui").open()
end

--- Close the life-grid UI, saving all note splits.
function M.close()
  require("recollect.ui").close()
end

--- Create (or open) today's daily note in the current window.
function M.create_daily_note()
  require("recollect.notes").create_today()
end

--- Open or create the daily note for a specific date.
---@param date_str string  Date in YYYY-MM-DD format
function M.jump_to_date(date_str)
  require("recollect.notes").open_or_create(date_str)
end

return M
