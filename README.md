# recollect 

Nvim Plugin to visualize, compare and edit Notes on a Grid. WIP

- Checks a folder for all files with the format: "YYYY-MM-DD.md" and
  places them on a grid for a visual feedback.
- The Grid has 2 Modes:
1. renders for a Years, always starting the dots on 1st of January 
2. renders from/til your Custom dates (Project start or your Birthday or whatever) 

- Plugin can read your YAML frontmatter; that means automatically changing
   symbols based on the tags you set in your .md files. 
- Grid shows Current date; Years, Months, Days, And a counter since the
   Grid strarting Date, aswell as the Weekday of the Dot your cursor
   is on. 
- you can highlight and edit time periods. 
- integrates into obsidian.nvim plugin
- check the Keybindings for possible toggles regarding split and
  rendering behaviour

This is a personal project and many parts are vibe coded after hours
of researching and already drinking too much coffe for my totally
unrelated master thesis. Since I switched from Obsidian to Nvim for
all notetaking and writing, I was missing a option to visually see my
dailies and so this was born. No programming background so if anyone
is interestet to vet or refactor, i would appreciate that! 

## Preview

![Preview Main](https://github.com/user-attachments/assets/6a7167b6-914f-4ef6-a78f-8d6157113fb1)

![Preview Details](https://github.com/user-attachments/assets/fbe282fc-ed3e-496d-9c0f-a00feef2744a)

## Usage
Open Recollect: 

```
:Recollect
```

you can always press '?' for help. 

## Default Keybindings


| Key | Description |
|:---|:---|
| **Navigation** | |
| `j/k/b/w` | Move cursor |
| `t` | Jump to today |
| `/` | Search date (YYYY-MM-DD) |
| `[` | Jump to previous note |
| `]` | Jump to next note |
| **Actions** | |
| `<Enter>` | Open in split |
| `D` | Delete note |
| `f` | Fuzzy search notes content |
| `r` | Refresh cache |
| `x` | Close all splits (`:q all`) |
| `X` | Write and quit all splits (`:wq all`) |
| `m` | Manage periods |
| **Toggles** | |
| `s` | Toggle split behaviour |
| `p` | Toggle note preview |
| `Y` | Toggle year view |
| `g` | Toggle Calendar/Year grid |
| `P` | Toggle period colors |
| **Other** | |
| `q` | Close Recollect |
| `?` | Show this help |



## Installation / Config
### Install with Lazy: 

```lua
-- ~/.config/nvim/lua/plugins/recollect.lua
return {
  "jbuck95/recollect.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("recollect").setup({
      -- All configuration options are optional.
      -- Below are some examples you can override.
      
      -- The start date for your grid.
      birthday = "1990-01-01",
      
      -- The path to your daily notes folder.
      -- IMPORTANT: Make sure to change this to your actual notes path.
      daily_notes_path = vim.fn.expand("~") .. "/Documents/Notes/Dailies",
      
      -- A function to generate the content for a new daily note.
      note_template = function(date_str)
        local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
        local date_obj = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day)})
        
        local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
        local months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
        
        local wday = tonumber(os.date("%w", date_obj)) + 1
        local formatted_date = string.format("%s, %d %s %s", weekdays[wday], tonumber(day), months[tonumber(month)], year)
        
        return string.format([[---
date: %s
---
### %s


]], date_str, formatted_date)
      end,

      -- You can define custom time periods that get highlighted in the grid.
      -- periods = {
        {
          start = "2020-03-11",
          finish = "2022-05-01",
          color = "red",
          label = "Pandemic"
        },
      },

      -- Symbols used for notes that have a specific tag in their YAML frontmatter.
      tag_symbols = {
        birthday = "🎂",
        event = "🎉",
        gym = "💪🏼",
        trip = "✈️",
        holiday = "☘",
        party = "🍻",
        work = "💼",
        project = "🛠️",
        deadline = "❗",
        health = "❤️",
        special = "⭐",
      },

      -- Customize the colors of the grid.
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
    })
    		-- Keymaps:
		vim.keymap.set("n", "<leader>rc", "<cmd>Recollect<cr>", { desc = "Open Recollect" })
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "recollect",
			callback = function()
				local map = function(lhs, plug, desc)
					vim.keymap.set("n", lhs, plug, { buffer = true, remap = true, silent = true, desc = desc })
				end

				-- Navigation
				map("t",     "<Plug>(recollect-today)",          "Jump to today")
				map("/",     "<Plug>(recollect-search-date)",    "Jump to date")
				map("[",     "<Plug>(recollect-prev-note)",      "Previous note")
				map("]",     "<Plug>(recollect-next-note)",      "Next note")
				map("f",     "<Plug>(recollect-search-content)", "Fuzzy search notes")

				-- Actions
				map("<CR>",  "<Plug>(recollect-open-note)",      "Open / create note")
				map("D",     "<Plug>(recollect-delete-note)",    "Delete note")
				map("r",     "<Plug>(recollect-refresh)",        "Refresh cache")
				map("x",     "<Plug>(recollect-close-splits)",   "Close splits")
				map("X",     "<Plug>(recollect-write-splits)",   "Save & close splits")
				map("m",     "<Plug>(recollect-manage-periods)", "Manage periods")

				-- Toggles
				map("s",     "<Plug>(recollect-toggle-split)",   "Toggle split mode")
				map("p",     "<Plug>(recollect-preview)",        "Toggle preview")
				map("P",     "<Plug>(recollect-toggle-periods)", "Toggle period colors")
				map("R",     "<Plug>(recollect-filter-periods)", "Toggle period filter")
				map("g",     "<Plug>(recollect-toggle-grid)",    "Toggle life/calendar grid")
				map("Y",     "<Plug>(recollect-year-view)",      "Year view")

				-- Other
				map("q",     "<Plug>(recollect-quit)",           "Close Recollect")
				map("?",     "<Plug>(recollect-help)",           "Show help")
			end,
		})

		-- Periods window keymaps (buffer-local, active inside the Periods popup)
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "recollect_periods",
			callback = function()
				local map = function(lhs, plug, desc)
					vim.keymap.set("n", lhs, plug, { buffer = true, remap = true, silent = true, desc = desc })
				end

				map("j",    "<Plug>(recollect-periods-next)",   "Next period")
				map("k",    "<Plug>(recollect-periods-prev)",   "Previous period")
				map("a",    "<Plug>(recollect-periods-add)",    "Add period")
				map("e",    "<Plug>(recollect-periods-edit)",   "Edit period")
				map("<CR>", "<Plug>(recollect-periods-edit)",   "Edit period")
				map("d",    "<Plug>(recollect-periods-delete)", "Delete period")
				map("q",    "<Plug>(recollect-periods-quit)",   "Close periods")
			end,
		})
  end,
}
```

### Config
you can configure further in the config.lua. For e.g. the Tag-Symbols or
periods (if you define periods in recall, they get saved in your nvim
folder as recollect.json)

yaml-frontmatter example: 
```
---
id: testnote
aliases: []
tags:
  - deadline
  - work
---
```

In config.lua:
```

  periods = {
    
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
```

## Todo: 
- [ ] rework periods 
- [ ] timers 
- [x] days_since / days_until


## Credits

- This plugin is heavily inspired by the [obsidian-life-grid](https://github.com/mrdonado/obsidian-life-grid) plugin!

## License

MIT
