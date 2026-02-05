local M = {}
local config = require("recollect.config")
local grid = require("recollect.grid")
local notes = require("recollect.notes")
local periods = require("recollect.periods")

M.buf = nil
M.win = nil
M.ns = vim.api.nvim_create_namespace("recollect")
M.days = {}
M.days_lived = 0
M.current_highlights = {}
M.preview_buf = nil
M.preview_win = nil
M.date_buf = nil
M.date_win = nil
M.preview_enabled = false
M.periods_enabled = true
M.filter_long_periods = false
M.current_year_view = nil
M.note_win_ids = {}
M.split_strategy = nil

local function setup_highlights()
	local cfg = config.get()

	vim.api.nvim_set_hl(0, "recollectDefault", { fg = cfg.colors.default_dot })
	vim.api.nvim_set_hl(0, "recollectToday", { fg = cfg.colors.today_dot, bold = true })
	vim.api.nvim_set_hl(0, "recollectNote", { fg = cfg.colors.note_exists })
	vim.api.nvim_set_hl(0, "recollectYearHeader", { fg = cfg.colors.year_header, bold = true })
	vim.api.nvim_set_hl(0, "recollectText", { fg = cfg.colors.text })
	vim.api.nvim_set_hl(0, "recollectSelected", { fg = "#ffffff", bg = "#585b70", bold = true })
	vim.api.nvim_set_hl(0, "recollectPreBirth", { fg = cfg.colors.default_dot })
end

local function get_day_display(day)
	if day.is_pre_birth then
		return "·", "recollectPreBirth", nil, nil
	end

	local char = "●"
	local hl = "recollectDefault"
	local bg_hl = nil

	if M.periods_enabled and day.period_color then
		local color_name = day.period_color
		bg_hl = "recollectPeriod_" .. color_name
		if vim.fn.hlexists(bg_hl) == 0 then
			local cfg = config.get()
			local color = cfg.colors[color_name] or color_name
			vim.api.nvim_set_hl(0, bg_hl, { bg = color })
		end
	end

	local metadata = notes.get_metadata(day.date)
	if metadata.color then
		local custom_hl = "recollectCustom" .. day.date:gsub("-", "")
		if vim.fn.hlexists(custom_hl) == 0 then
			vim.api.nvim_set_hl(0, custom_hl, { fg = metadata.color })
		end
		return char, custom_hl, metadata.eventName, bg_hl
	end

	local cfg = config.get()
	local custom_symbol_found = false
	if metadata.tags and cfg.tag_symbols then
		local tags = metadata.tags
		if type(tags) == "string" then
			tags = { tags } -- handle single tag case
		end

		if type(tags) == "table" then
			for _, tag in ipairs(tags) do
				if cfg.tag_symbols[tag] then
					char = cfg.tag_symbols[tag]
					custom_symbol_found = true
					break -- use first matching tag
				end
			end
		end
	end

	if day.is_today then
		char = "󰣙"
		hl = "recollectToday"
	elseif custom_symbol_found then
		hl = "recollectNote"
	elseif notes.note_exists(day.date) then
		char = "●"
		hl = "recollectNote"
	elseif day.is_future then
		char = "○"
	end

	return char, hl, metadata.eventName, bg_hl
end

local function render_grid()
	if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

	vim.api.nvim_buf_set_option(M.buf, "modifiable", true)

	local lines = {}
	local highlights = {}

	local days_per_row = 25
	local days_per_year = 364
	local width = days_per_row * 3 + 10

	table.insert(lines, "╔" .. string.rep("═", width - 2) .. "╗")
	local title
	if config.get().grid_mode == "year" and M.current_year_view then
		title = "Y E A R   G R I D - " .. M.current_year_view
	elseif config.get().grid_mode == "calendar" then
		title = "C A L E N D A R   G R I D"
	else
		title = "L I F E   G R I D"
	end
	local padding = math.floor((width - #title - 2) / 2)
	table.insert(lines, "║" .. string.rep(" ", padding) .. title .. string.rep(" ", width - padding - #title - 2) .. "║")
	table.insert(lines, "╚" .. string.rep("═", width - 2) .. "╝")
	table.insert(lines, "")

	local cfg = config.get()
	if config.get().grid_mode == "life" then
		local birthday = grid.parse_date(cfg.birthday)
		local today_parsed = grid.parse_date(os.date("%Y-%m-%d"))
		local years, months, days = grid.age_detailed(birthday, today_parsed)
		table.insert(lines, string.format("  Born: %s  |  Age: %dY %02dM %02dD  |  Days lived: %d / %d",
			cfg.birthday,
			years, months, days,
			M.days_lived,
			cfg.max_age * 365
		))
		table.insert(lines, "")
	elseif config.get().grid_mode == "year" and M.current_year_view then
		table.insert(lines, string.format("  Year: %d", M.current_year_view))
		table.insert(lines, "")
	elseif config.get().grid_mode == "calendar" then
		-- No specific info line for calendar view, just a blank line for spacing
		table.insert(lines, "")
	end

	local current_display_year = tonumber(os.date("%Y"))
	local relevant_periods = {}
	for _, period in ipairs(cfg.periods) do
		local duration = grid.period_duration_in_days(period)
		if grid.period_overlaps_year(period, current_display_year) then
			if M.filter_long_periods then
				if duration <= 300 then
					table.insert(relevant_periods, period)
				end
			else
				table.insert(relevant_periods, period)
			end
		end
	end

	if #relevant_periods > 0 then
		table.insert(lines, string.format("  Periods in %d:", current_display_year))
		for _, period in ipairs(relevant_periods) do
			table.insert(lines, string.format("    - %s (%s - %s)", period.label, period.start, period.finish))
		end
		table.insert(lines, "")
	end

	table.insert(lines, "  [●] Past  [󰣙] Today  [○] Future  |  Green = Note exists")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, "")

	local current_year_header = -1
	local day_counter = 0

	for day_idx = 1, #M.days do
		local day = M.days[day_idx]
		local year_for_header

		if config.get().grid_mode == "life" then
			year_for_header = day.age
		else -- "calendar" or "year"
			year_for_header = day.year
		end


		if year_for_header ~= current_year_header then
			if current_year_header >= 0 then
				table.insert(lines, "")
			end
			current_year_header = year_for_header
			day_counter = 0

			local header_text
			if config.get().grid_mode == "life" then
				header_text = string.format("  %2d  ", year_for_header)
			else
				header_text = string.format("  %4d  ", year_for_header)
			end
			table.insert(lines, header_text)
			table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = #header_text, hl_group = "recollectYearHeader" })
		end

		if day_counter % days_per_row == 0 then
			table.insert(lines, "")
		end

		local current_line_idx = #lines
		local current_line = lines[current_line_idx] or ""

		local char, hl, event, bg_hl = get_day_display(day)

		local cell_display
		if vim.fn.strwidth(char) > 1 then
			cell_display = char .. " "
		else
			cell_display = " " .. char .. " "
		end

		local col_start = #current_line
		lines[current_line_idx] = current_line .. cell_display

		if bg_hl then
			table.insert(highlights, {
				line = current_line_idx - 1,
				col_start = col_start,
				col_end = col_start + #cell_display,
				hl_group = bg_hl,
				day_idx = day_idx
			})
		end

		table.insert(highlights, {
			line = current_line_idx - 1,
			col_start = col_start,
			col_end = col_start + #cell_display,
			hl_group = hl,
			day_idx = day_idx
		})

		day_counter = day_counter + 1
	end

	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, "  Press Enter to open/create note.")
	table.insert(lines, "  q: quit | x: close splits | X: wq splits | j/k: scroll | t: today | r: refresh | p: preview | P: periods | g: grids | Y: Year grid | s: split mode | m: manage | ?: help")

	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)

	M.current_highlights = highlights
	for _, h in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(M.buf, M.ns, h.hl_group, h.line, h.col_start, h.col_end)
	end

	vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

local function find_day_at_cursor()
	local cursor = vim.api.nvim_win_get_cursor(M.win)
	local line = cursor[1] - 1
	local col = cursor[2]

	for _, h in ipairs(M.current_highlights or {}) do
		if h.line == line and h.day_idx and col >= h.col_start and col < h.col_end then
			return h.day_idx
		end
	end

	return nil
end

local function update_date_display()
    local day_idx = find_day_at_cursor()
    if day_idx and M.days[day_idx] and M.date_buf and vim.api.nvim_buf_is_valid(M.date_buf) then
        local day = M.days[day_idx]
        local date_str = string.format("%s", day.date)
        local cfg = config.get()
        local birthday = grid.parse_date(cfg.birthday)
        local current_date = grid.parse_date(date_str)
        local years, months, days = grid.age_detailed(birthday, current_date)
        
        local timestamp = grid.date_to_timestamp(current_date)
        local weekday
        -- Temporarily set locale for weekday formatting
        local original_locale = os.setlocale(nil, "time")
        local success, result = pcall(function()
            os.setlocale(cfg.locale, "time")
            local day_name = os.date("%A", timestamp)
            os.setlocale(original_locale, "time")
            return day_name
        end)

        if success and result then
            weekday = result
        else
            -- Fallback to 'C' locale if the configured one fails
            os.setlocale("C", "time")
            weekday = os.date("%A", timestamp)
            os.setlocale(original_locale, "time")
        end

        local display_str = string.format(" %dY %02dM %02dD\n %s,\n %s", years, months, days, weekday, date_str)
        
        vim.api.nvim_buf_set_lines(M.date_buf, 0, -1, false, vim.split(display_str, "\n"))
    else
        if M.date_buf and vim.api.nvim_buf_is_valid(M.date_buf) then
            vim.api.nvim_buf_set_lines(M.date_buf, 0, -1, false, {''})
        end
    end
end

local function show_note_preview()
	if not M.preview_enabled then return end

	local day_idx = find_day_at_cursor()
	if not day_idx or not M.days[day_idx] then
		if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
			vim.api.nvim_win_close(M.preview_win, true)
		end
		if M.preview_buf and vim.api.nvim_buf_is_valid(M.preview_buf) then
			vim.api.nvim_buf_delete(M.preview_buf, { force = true })
		end
		M.preview_win = nil
		M.preview_buf = nil
		return
	end

	local date_str = M.days[day_idx].date
	local cfg = config.get()
	local filepath = cfg.daily_notes_path .. "/" .. date_str .. ".md"

	if vim.fn.filereadable(filepath) == 0 then
		if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
			vim.api.nvim_win_close(M.preview_win, true)
		end
		if M.preview_buf and vim.api.nvim_buf_is_valid(M.preview_buf) then
			vim.api.nvim_buf_delete(M.preview_buf, { force = true })
		end
		M.preview_win = nil
		M.preview_buf = nil
		return
	end

	local file = io.open(filepath, "r")
	if not file then return end
	local content = file:read("*all")
	file:close()

	if not M.preview_buf or not vim.api.nvim_buf_is_valid(M.preview_buf) then
		M.preview_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_option(M.preview_buf, "filetype", "markdown")
		vim.api.nvim_buf_set_option(M.preview_buf, "bufhidden", "wipe")
	end

	vim.api.nvim_buf_set_lines(M.preview_buf, 0, -1, false, vim.split(content, "\n"))

	local vertical_split_threshold = 120
	local win_width = vim.api.nvim_win_get_width(M.win)
	local use_wide_preview = win_width > vertical_split_threshold

	local width, height, row, col

	if use_wide_preview then
		local grid_width = 70
		local margin = 13
		width = vim.o.columns - grid_width - (margin * 3)
		height = vim.o.lines - 4
		row = 1
		col = 109 - margin
	else
		local max_height = math.floor(vim.o.lines * 0.35)
		height = math.min(max_height, #vim.split(content, "\n"))
		width = math.min(80, vim.o.columns - 10)
		row = 1
		col = math.floor((vim.o.columns - width) / 2)
	end

	if not M.preview_win or not vim.api.nvim_win_is_valid(M.preview_win) then
		M.preview_win = vim.api.nvim_open_win(M.preview_buf, false, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
		})
		vim.api.nvim_win_set_option(M.preview_win, "winhl", "Normal:recollectText")
	else
		vim.api.nvim_win_set_config(M.preview_win, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
		})
	end
end

local function toggle_note_preview()
	M.preview_enabled = not M.preview_enabled
	if M.preview_enabled then
		show_note_preview()
	else
		if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
			vim.api.nvim_win_close(M.preview_win, true)
		end
		if M.preview_buf and vim.api.nvim_buf_is_valid(M.preview_buf) then
			vim.api.nvim_buf_delete(M.preview_buf, { force = true })
		end
		M.preview_win = nil
		M.preview_buf = nil
	end
end

local function handle_narrow_split(filepath, current_grid_win)
	-- NARROW: First horizontal, second vertical
	if #M.note_win_ids == 0 then
		vim.api.nvim_command("belowright split " .. vim.fn.fnameescape(filepath))
		table.insert(M.note_win_ids, vim.api.nvim_get_current_win())
		vim.api.nvim_set_current_win(current_grid_win)
	elseif #M.note_win_ids == 1 then
		vim.api.nvim_set_current_win(M.note_win_ids[1])
		vim.api.nvim_command("rightbelow vsplit " .. vim.fn.fnameescape(filepath))
		table.insert(M.note_win_ids, vim.api.nvim_get_current_win())
		vim.api.nvim_set_current_win(current_grid_win)
	else
		local oldest_win_id = table.remove(M.note_win_ids, 1)
		local buf = vim.fn.bufnr(filepath)
		if buf == -1 then buf = vim.api.nvim_create_buf(true, false) end
		vim.api.nvim_buf_set_name(buf, filepath)
		vim.api.nvim_win_set_buf(oldest_win_id, buf)
		vim.api.nvim_buf_call(buf, function() vim.cmd("edit") end)
		table.insert(M.note_win_ids, oldest_win_id)
		vim.api.nvim_set_current_win(current_grid_win)
	end
end

local function handle_wide_split(filepath, current_grid_win)
	-- WIDE: First vertical, second horizontal UNDER the first
	if #M.note_win_ids == 0 then
		vim.api.nvim_command("rightbelow vsplit " .. vim.fn.fnameescape(filepath))
		table.insert(M.note_win_ids, vim.api.nvim_get_current_win())
		vim.api.nvim_set_current_win(current_grid_win)
	elseif #M.note_win_ids == 1 then
		-- Get dimensions of the first note window
		local first_win = M.note_win_ids[1]
		vim.fn.win_gotoid(first_win)

		vim.api.nvim_command("belowright split " .. vim.fn.fnameescape(filepath))
		local new_win = vim.api.nvim_get_current_win()

		table.insert(M.note_win_ids, new_win)
		vim.api.nvim_set_current_win(current_grid_win)
	else
		local oldest_win_id = table.remove(M.note_win_ids, 1)
		local buf = vim.fn.bufnr(filepath)
		if buf == -1 then buf = vim.api.nvim_create_buf(true, false) end
		vim.api.nvim_buf_set_name(buf, filepath)
		vim.api.nvim_win_set_buf(oldest_win_id, buf)
		vim.api.nvim_buf_call(buf, function() vim.cmd("edit") end)
		table.insert(M.note_win_ids, oldest_win_id)
		vim.api.nvim_set_current_win(current_grid_win)
	end
end

local function open_note_split()
	if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
		vim.api.nvim_win_close(M.preview_win, true)
		M.preview_win = nil
	end
	if M.preview_buf and vim.api.nvim_buf_is_valid(M.preview_buf) then
		vim.api.nvim_buf_delete(M.preview_buf, { force = true })
		M.preview_buf = nil
	end

	local day_idx = find_day_at_cursor()
	if day_idx and M.days[day_idx] then
		local day = M.days[day_idx]
		local cfg = config.get()
		local filepath = cfg.daily_notes_path .. "/" .. day.date .. ".md"

		if vim.fn.isdirectory(cfg.daily_notes_path) == 0 then
			vim.fn.mkdir(cfg.daily_notes_path, "p")
		end

		if vim.fn.filereadable(filepath) == 0 then
			local file = io.open(filepath, "w")
			if file then
				file:write(cfg.note_template(day.date))
				file:close()
			end
		end

		local vertical_split_threshold = 120
		local win_width = vim.api.nvim_win_get_width(M.win)
		local current_grid_win = vim.api.nvim_get_current_win()

		-- Clean up invalid windows
		local valid = {}
		for _, win_id in ipairs(M.note_win_ids) do
			if vim.api.nvim_win_is_valid(win_id) then
				table.insert(valid, win_id)
			end
		end
		M.note_win_ids = valid

		local cfg = config.get()
		if cfg.note_split_mode == "reuse" and #M.note_win_ids > 0 then
			-- A note window already exists, so replace its buffer
			local note_win_id = M.note_win_ids[1]
			local buf = vim.fn.bufnr(filepath, true)
			vim.api.nvim_win_set_buf(note_win_id, buf)
			vim.api.nvim_buf_call(buf, function() vim.cmd("edit") end)
			vim.api.nvim_set_current_win(current_grid_win)
		else
			-- This handles both "split" mode and the first open in "reuse" mode
			local effective_split_strategy = M.split_strategy
			if not effective_split_strategy then
				if win_width <= vertical_split_threshold then
					effective_split_strategy = "narrow"
				else
					effective_split_strategy = "wide"
				end
				M.split_strategy = effective_split_strategy -- Store for subsequent calls
			end

			if effective_split_strategy == "narrow" then
				handle_narrow_split(filepath, current_grid_win)
			else
				handle_wide_split(filepath, current_grid_win)
			end
		end

		notes.build_cache()
	end
end

local function toggle_periods_display()
	M.periods_enabled = not M.periods_enabled
	render_grid()
	local status = M.periods_enabled and "enabled" or "disabled"
	vim.notify("Period colors " .. status, vim.log.levels.INFO)
end

local function toggle_period_filter()
	M.filter_long_periods = not M.filter_long_periods
	render_grid()
	local status = M.filter_long_periods and "enabled" or "disabled"
	vim.notify("Long period filter " .. status, vim.log.levels.INFO)
end

local function close_all_note_splits()
	if #M.note_win_ids == 0 then
		vim.notify("No note splits to close.", vim.log.levels.INFO)
		return
	end
	local original_win = vim.api.nvim_get_current_win()
	local had_error = false
	local closed_count = 0
	-- Use a copy as the autocommand on WinClosed will modify the table
	local win_ids_copy = {}
	for _, id in ipairs(M.note_win_ids) do table.insert(win_ids_copy, id) end

	for _, win_id in ipairs(win_ids_copy) do
		if vim.api.nvim_win_is_valid(win_id) then
			local success, err = pcall(vim.api.nvim_win_close, win_id, false)
			if success then
				closed_count = closed_count + 1
			else
				had_error = true
			end
		end
	end
	M.split_strategy = nil -- Reset split strategy
	vim.api.nvim_set_current_win(original_win)
	if had_error then
		vim.notify("Could not close some splits (they may have unsaved changes).", vim.log.levels.WARN)
	elseif closed_count > 0 then
		vim.notify("Closed " .. closed_count .. " note split(s).", vim.log.levels.INFO)
	end
end

local function write_and_close_all_note_splits()
	if #M.note_win_ids == 0 then
		vim.notify("No note splits to close.", vim.log.levels.INFO)
		return
	end
	local original_win = vim.api.nvim_get_current_win()
	local closed_count = 0
	local win_ids_copy = {}
	for _, id in ipairs(M.note_win_ids) do table.insert(win_ids_copy, id) end

	for _, win_id in ipairs(win_ids_copy) do
		if vim.api.nvim_win_is_valid(win_id) then
			local buf_id = vim.api.nvim_win_get_buf(win_id)
			vim.api.nvim_buf_call(buf_id, function()
				vim.cmd('write')
			end)
			vim.api.nvim_win_close(win_id, false)
			closed_count = closed_count + 1
		end
	end
	M.split_strategy = nil -- Reset split strategy
	vim.api.nvim_set_current_win(original_win)
	if closed_count > 0 then
		vim.notify("Saved and closed " .. closed_count .. " note split(s).", vim.log.levels.INFO)
	end
end

local function toggle_note_split_mode()
	local cfg = config.get()
	if cfg.note_split_mode == "split" then
		cfg.note_split_mode = "reuse"
		vim.notify("Note split mode: Reuse (single note)", vim.log.levels.INFO)
	else
		cfg.note_split_mode = "split"
		vim.notify("Note split mode: Split (multiple notes)", vim.log.levels.INFO)
	end
	-- Only close splits if there are any to close, preventing the unwanted message
	if #M.note_win_ids > 0 then
		close_all_note_splits()
	end
end

local function confirm_delete_note()
	local day_idx = find_day_at_cursor()
	if not day_idx or not M.days[day_idx] then
		vim.notify("No day selected.", vim.log.levels.WARN)
		return
	end

	local day = M.days[day_idx]
	if not notes.note_exists(day.date) then
		vim.notify("No note exists for " .. day.date, vim.log.levels.INFO)
		return
	end

	vim.ui.input({ prompt = "Delete note for " .. day.date .. "? (y/n): ", default = "n" }, function(input)
		if input and (input:lower() == "y" or input:lower() == "yes") then
			local cfg = config.get()
			local filepath = cfg.daily_notes_path .. "/" .. day.date .. ".md"

			-- Close any open splits for this note before deleting
			local original_win = vim.api.nvim_get_current_win()
			local wins_to_close = {}
			for _, win_id in ipairs(M.note_win_ids) do
				if vim.api.nvim_win_is_valid(win_id) then
					local buf_id = vim.api.nvim_win_get_buf(win_id)
					local buf_name = vim.api.nvim_buf_get_name(buf_id)
					if buf_name == filepath then
						table.insert(wins_to_close, win_id)
					end
				end
			end

			for _, win_id in ipairs(wins_to_close) do
				vim.api.nvim_win_close(win_id, true)
			end
			-- Rebuild M.note_win_ids after closing windows
			local valid = {}
			for _, win_id in ipairs(M.note_win_ids) do
				if vim.api.nvim_win_is_valid(win_id) then
					table.insert(valid, win_id)
					end
				end
			M.note_win_ids = valid
			vim.api.nvim_set_current_win(original_win)


			if notes.delete_note(day.date) then
				vim.notify("Note for " .. day.date .. " deleted.", vim.log.levels.INFO)
				render_grid()
				if M.preview_enabled then show_note_preview() end
			else
				vim.notify("Failed to delete note for " .. day.date, vim.log.levels.ERROR)
			end
		else
			vim.notify("Note deletion cancelled.", vim.log.levels.INFO)
		end
	end)
end

local function setup_keymaps()
	local opts = { buffer = M.buf, nowait = true, silent = true }

	local function jump_to_today()
		for i, day in ipairs(M.days) do
			if day.is_today then
				for _, h in ipairs(M.current_highlights) do
					if h.day_idx == i then
						vim.api.nvim_win_set_cursor(M.win, { h.line + 1, h.col_start + 1 })
						vim.cmd("normal! zz")
						return
					end
				end
				break -- Found today, no need to continue outer loop
			end
		end
	end

	vim.keymap.set("n", "q", function() M.close() end, opts)
	vim.keymap.set("n", "x", close_all_note_splits, opts)
	vim.keymap.set("n", "X", write_and_close_all_note_splits, opts)
	vim.keymap.set("n", "D", confirm_delete_note, opts)

	vim.keymap.set("n", "j", "j", opts)
	vim.keymap.set("n", "k", "k", opts)
	vim.keymap.set("n", "h", "h", opts)
	vim.keymap.set("n", "l", "l", opts)
	vim.keymap.set("n", "<C-d>", "<C-d>", opts)
	vim.keymap.set("n", "<C-u>", "<C-u>", opts)

	vim.keymap.set("n", "<CR>", function()
		open_note_split()
	end, opts)

    vim.keymap.set("n", "s", toggle_note_split_mode, opts)

	vim.keymap.set("n", "r", function()
		notes.build_cache()
		M.days, M.days_lived = grid.generate_life_days()
		render_grid()
		vim.notify("Recollect refreshed", vim.log.levels.INFO)
	end, opts)

	vim.keymap.set("n", "t", jump_to_today, opts)

	vim.keymap.set("n", "/", function()
		vim.ui.input({ prompt = "Jump to date (YYYY-MM-DD): " }, function(input)
			if not input then return end
			input = input:gsub("%.", "-")
			for i, day in ipairs(M.days) do
				if day.date == input then
					for _, h in ipairs(M.current_highlights) do
						if h.day_idx == i then
							vim.api.nvim_win_set_cursor(M.win, {h.line + 1, h.col_start + 1})
							vim.cmd("normal! zz")
							render_grid()
							if M.preview_enabled then show_note_preview() end
							vim.notify("Jumped to " .. input, vim.log.levels.INFO)							return
						end
					end
				end
			end
			vim.notify("Date not found: " .. input, vim.log.levels.WARN)
		end)
	end, opts)

	vim.keymap.set("n", "p", function()
		toggle_note_preview()
	end, opts)

	vim.keymap.set("n", "P", function()
		toggle_periods_display()
	end, opts)

	vim.keymap.set("n", "R", function()
		toggle_period_filter()
	end, opts)

	vim.keymap.set("n", "g", function()
		local cfg = config.get()
		if cfg.grid_mode == "life" then
			cfg.grid_mode = "calendar"
			M.days, M.days_lived = grid.generate_calendar_years_days()
		else -- calendar or year -> life
			cfg.grid_mode = "life"
			M.days, M.days_lived = grid.generate_life_days()
		end
		render_grid()
		jump_to_today()
	end, opts)

	vim.keymap.set("n", "Y", function()
		local cfg = config.get()
		cfg.grid_mode = "year"
		local day_idx = find_day_at_cursor()
		if day_idx and M.days[day_idx] then
			M.current_year_view = M.days[day_idx].year
		else
			M.current_year_view = tonumber(os.date("%Y"))
		end
		M.days, M.days_lived = grid.generate_year_days(M.current_year_view)
		render_grid()
		jump_to_today()
	end, opts)

	vim.keymap.set("n", "m", function()
		periods.open({
			on_close = function()
				M.days, M.days_lived = grid.generate_life_days()
				render_grid()
				vim.notify("Recollect refreshed", vim.log.levels.INFO)
			end
		})
	end, opts)

	vim.keymap.set("n", "[", function()
		local current_idx = find_day_at_cursor() or 1
		for i = current_idx - 1, 1, -1 do
			if notes.note_exists(M.days[i].date) then
				for _, h in ipairs(M.current_highlights) do
					if h.day_idx == i then
						vim.api.nvim_win_set_cursor(M.win, {h.line + 1, h.col_start + 1})						vim.cmd("normal! zz")
						render_grid()
						if M.preview_enabled then show_note_preview() end
						vim.notify("Jumped to previous note: " .. M.days[i].date, vim.log.levels.INFO)
						return
					end
				end
			end
		end
		vim.notify("No previous note found", vim.log.levels.WARN)
	end, opts)

	vim.keymap.set("n", "]", function()
		local current_idx = find_day_at_cursor() or 1
		for i = current_idx + 1, #M.days do
			if notes.note_exists(M.days[i].date) then
				for _, h in ipairs(M.current_highlights) do
					if h.day_idx == i then
						vim.api.nvim_win_set_cursor(M.win, {h.line + 1, h.col_start + 1})
						vim.cmd("normal! zz")
						render_grid()
						if M.preview_enabled then show_note_preview() end
						vim.notify("Jumped to next note: " .. M.days[i].date, vim.log.levels.INFO)
						return
					end
				end
			end
		end
		vim.notify("No next note found", vim.log.levels.WARN)
	end, opts)

	    vim.keymap.set("n", "f", function()
	        local cfg = config.get()
	        local current_win_width = vim.api.nvim_win_get_width(0)
	        local vertical_preview_threshold = 120 -- Reuse the existing threshold
	
	        local previewer_config = {}
	        if current_win_width > vertical_preview_threshold then
	            -- Wide window: vertical preview
	                        previewer_config = {
	                            layout_strategy = "horizontal",
	                            layout_config = {
	                                horizontal = {
	                                    width = 0.5,
	                                    height = 0.8, -- Adjust as needed
	                                    preview_height = 0.7,
	                                },
	                            },
	                        }
	                    else
	                        -- Narrow window: vertical preview
	                        previewer_config = {
	                            layout_strategy = "vertical",
	                            layout_config = {
	                                vertical = {
	                                    width = 0.9, -- Adjust as needed
	                                    height = 0.9,
	                                    preview_width = 0.7,
	                                    preview_height = 0.7,
	                                },
	                            },
	                        }	        end
	
	        require('telescope.builtin').live_grep({
	            cwd = cfg.daily_notes_path,
	            prompt_title = "Search Notes Content",
	            layout_strategy = previewer_config.layout_strategy,
	            layout_config = previewer_config.layout_config,
	            attach_mappings = function(_, map)
	                map('i', '<CR>', function(prompt_bufnr)
	                    local selection = require('telescope.actions.state').get_selected_entry()
	                    require('telescope.actions').close(prompt_bufnr)
	                    if selection then
	                        local filepath = selection.filename
	                        local date = filepath:match("(%d%d%d%d%-%d%d%-%d%d)%.md$")
	                        if date then
	                            for i, day in ipairs(M.days) do
	                                if day.date == date then
	                                    for _, h in ipairs(M.current_highlights) do
	                                        if h.day_idx == i then
	                                            vim.api.nvim_win_set_cursor(M.win, {h.line + 1, h.col_start + 1})
	                                            vim.cmd("normal! zz")
	                                            render_grid()
	                                            if M.preview_enabled then show_note_preview() end
	                                            return
	                                        end
	                                    end
	                                end
	                            end
	                        end
	                        vim.cmd("edit " .. filepath)
	                    end
	                end)
	                return true
	            end
	        })
	    end, opts)
	vim.keymap.set("n", "?", function()
		local help_lines = {
			"  ╔═══════════════════════════════════════╗",
			"  ║           Recollect HELP              ║",
			"  ╚═══════════════════════════════════════╝",
			"",
			"Navigation:",
			"  j/k/b/w     - Move cursor",
			"  <C-d>/<C-u> - Scroll half page",
			"  t           - Jump to today",
			"  /           - Search date (YYYY-MM-DD)",
			"  [           - Jump to previous note",
			"  ]           - Jump to next note",
			"",
			"Actions:",
			"  <Enter>     - Open in split",
			"  D           - Delete note",
			"  f           - Fuzzy search notes content",
			"  r           - Refresh cache",
			"  x           - :q all splits ",
			"  X           - :wq all splits ",
			"  m           - Manage periods",
			"",
			"Toggles:",
			"  s           - Toggle split behaviour ",
			"  p           - Toggle note preview",
			"  Y           - Toggle year view",
			"  g           - Toggle Calendar/Year grid",
			"  P           - Toggle period colors",
			"",
			"Other:",
			"  q			     - Close Recollect",
			"  ?           - Show this help",
			"",
			"Press any key to close...",
		}

		local help_buf = vim.api.nvim_create_buf(false, true)
		local help_win = vim.api.nvim_open_win(help_buf, true, {
			relative = "editor",
			width = 45,
			height = #help_lines,
			col = math.floor((vim.o.columns - 45) / 2),
			row = math.floor((vim.o.lines - #help_lines) / 2),
			style = "minimal",
			border = "rounded",
		})

		vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
		vim.api.nvim_buf_set_option(help_buf, "modifiable", false)

		vim.keymap.set("n", "<CR>", function()
			vim.api.nvim_win_close(help_win, true)
		end, { buffer = help_buf, nowait = true })

		vim.keymap.set("n", "q", function()
			vim.api.nvim_win_close(help_win, true)
		end, { buffer = help_buf, nowait = true })
	end, opts)
end

function M.open()
	setup_highlights()
	notes.build_cache()
	periods.load_periods()

	local cfg = config.get()
	if cfg.grid_mode == "year" then
		M.current_year_view = tonumber(os.date("%Y"))
		M.days, M.days_lived = grid.generate_year_days(M.current_year_view)
	elseif cfg.grid_mode == "calendar" then
		M.days, M.days_lived = grid.generate_calendar_years_days()
	else
		M.days, M.days_lived = grid.generate_life_days()
	end

	M.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(M.buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.buf, "filetype", "recollect")
	vim.api.nvim_buf_set_name(M.buf, "Recollect")

	M.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(M.win, M.buf)

	render_grid()
	setup_keymaps()

	M.date_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(M.date_buf, 'buftype', 'nofile')
	vim.api.nvim_buf_set_option(M.date_buf, 'bufhidden', 'wipe')
	M.date_win = vim.api.nvim_open_win(M.date_buf, false, {
		relative = 'editor',
		row = 19,
		--		col = vim.o.columns - 14,
		col = 80,
		width = 12,
		height = 3,
		style = 'minimal',
		border = 'shadow',
		focusable = false,
	})
	vim.api.nvim_win_set_option(M.date_win, 'winhl', 'Normal:recollectText,FloatBorder:recollectGridLines')

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = M.buf,
		callback = function()
			update_date_display()
			if M.preview_enabled then show_note_preview() end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		callback = function(args)
			for i, win_id in ipairs(M.note_win_ids) do
				if win_id == args.winid then
					table.remove(M.note_win_ids, i)
					break
				end
			end
		end,
	})

	for i, day in ipairs(M.days) do		if day.is_today then
		for _, h in ipairs(M.current_highlights) do
			if h.day_idx == i then
				vim.api.nvim_win_set_cursor(M.win, {math.max(1, h.line + 1), h.col_start + 1})					vim.cmd("normal! zz")
				break
			end
		end
		break
	end
	end
end

function M.close()
	if M.win and vim.api.nvim_win_is_valid(M.win) then
		if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
			vim.api.nvim_buf_delete(M.buf, { force = true })
		end
	end
	if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
		vim.api.nvim_win_close(M.preview_win, true)
	end
	if M.preview_buf and vim.api.nvim_buf_is_valid(M.preview_buf) then
		vim.api.nvim_buf_delete(M.preview_buf, { force = true })
	end
	if M.date_win and vim.api.nvim_win_is_valid(M.date_win) then
		vim.api.nvim_win_close(M.date_win, true)
	end
	if M.date_buf and vim.api.nvim_buf_is_valid(M.date_buf) then
		vim.api.nvim_buf_delete(M.date_buf, { force = true })
	end
	M.buf = nil
	M.win = nil
	M.preview_buf = nil
	M.preview_win = nil
	M.date_buf = nil
	M.date_win = nil
	M.preview_enabled = false
	M.note_win_ids = {}
	M.split_strategy = nil
end

return M
