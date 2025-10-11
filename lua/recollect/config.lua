-- ~/.config/nvim/lua/recollect/config.lua
local M = {}

M.defaults = {
  birthday = "1990-01-01",
  max_age = 95,
  grid_mode = "life", -- "life", "year", or "calendar"
  locale = "en_US.UTF-8", -- Set the locale for date formatting
  note_split_mode = "split", -- "split" or "reuse"
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
  periods = {
    -- ...
  },
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

M.current = M.defaults

function M.set(opts)
  M.current = vim.tbl_deep_extend("force", M.current, opts or {})
end

function M.get()
  return M.current
end

return M
