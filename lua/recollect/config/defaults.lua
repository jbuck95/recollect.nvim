---@class recollect.ConfigDefaults
---@field birthday          string                     Birth date (YYYY-MM-DD)
---@field data_dir          string?                    Custom directory for data files (default: stdpath("config"))
---@field max_age           number                     Maximum age in years
---@field grid_mode         string                     "life" | "year" | "calendar"
---@field locale            string                     Locale for date formatting
---@field note_split_mode   string                     "split" | "reuse"
---@field daily_notes_path  string                     Path to daily notes directory
---@field daily_notes_format string                    strftime pattern for daily note filenames
---@field note_template     fun(date_str: string):string  Template for new daily notes
---@field periods           recollect.Period[]         Default period definitions
---@field bar_position      string                     "top" | "bottom"
---@field bar_offset        number?                    Extra row offset for the status bar
---@field tag_symbols       table<string,string>       Tag -> unicode symbol mapping
---@field colors            recollect.Colors           Highlight colour definitions
---@field tracked_tags      table<string,recollect.TagTracking>?  Telescope tag-picker configuration

---@class recollect.Period
---@field start   string   Start date (YYYY-MM-DD)
---@field finish  string   End date (YYYY-MM-DD or "present")
---@field label   string   Display label
---@field color   string   Key into colors table

---@class recollect.Colors
---@field background    string   HEX colour
---@field default_dot   string
---@field today_dot     string
---@field note_exists   string
---@field grid_lines    string
---@field text          string
---@field year_header   string
---@field yellow        string
---@field blue          string
---@field green         string
---@field red           string
---@field purple        string
---@field orange        string

---@class recollect.TagTracking
---@field label  string   Display label
---@field icon?  string   Unicode icon
---@field order? number   Sort order (lower = first)

local M = {
  birthday = "1990-01-01",
  data_dir = nil,
  max_age = 95,
  grid_mode = "life",
  locale = "en_US.UTF-8",
  note_split_mode = "reuse",
  daily_notes_path = vim.fn.expand("~") .. "/Documents/notes/dailies/",
  daily_notes_format = "%Y-%m-%d",
  note_template = function(date_str)
    return string.format(
      [[---
date: %s
---

### Tasks
- [ ] 

### Notes

]],
      date_str
    )
  end,
  periods = {},
  bar_position = "top",
  bar_offset = nil,
  tag_symbols = {
    birthday = "🎂",
    event = "🎉",
    gym = "💪🏼",
    trip = "✈️",
    feiertag = "☘",
    party = "🍻",
    work = "💼",
    tinker = "🛠️",
    deadline = "❗",
    deal = "🤝",
    personal = "👤",
    health = "❤️",
    special = "⭐",
    nasa = "🌠",
  },
  colors = {
    background = "#1e1e2e",
    default_dot = "#45475a",
    today_dot = "#f38ba8",
    note_exists = "#a6e3a1",
    grid_lines = "#313244",
    text = "#cdd6f4",
    year_header = "#89b4fa",
    yellow = "#f9e2af",
    blue = "#89b4fa",
    green = "#a6e3a1",
    red = "#f38ba8",
    purple = "#cba6f7",
    orange = "#fab387",
  },
}

return M
