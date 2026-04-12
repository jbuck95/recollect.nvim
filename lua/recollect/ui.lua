local M = {}
local config = require("recollect.config")
local grid = require("recollect.grid")
local notes = require("recollect.notes")
local periods = require("recollect.periods")
local recurring = require("recollect.recurring")

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

	vim.api.nvim_set_hl(0, "recollectDefault",    { fg = cfg.colors.default_dot })
	vim.api.nvim_set_hl(0, "recollectToday",       { fg = cfg.colors.today_dot, bold = true })
	vim.api.nvim_set_hl(0, "recollectNote",        { fg = cfg.colors.note_exists })
	vim.api.nvim_set_hl(0, "recollectYearHeader",  { fg = cfg.colors.year_header, bold = true })
	vim.api.nvim_set_hl(0, "recollectText",        { fg = cfg.colors.text })
	vim.api.nvim_set_hl(0, "recollectSelected",    { fg = "#ffffff", bg = "#585b70", bold = true })
	vim.api.nvim_set_hl(0, "recollectPreBirth",    { fg = cfg.colors.default_dot })
	vim.api.nvim_set_hl(0, "recollectTopBar",      { bg = "#313244", fg = "#cdd6f4", bold = true })
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
		if type(tags) == "string" then tags = { tags } end
		if type(tags) == "table" then
			for _, tag in ipairs(tags) do
				if cfg.tag_symbols[tag] then
					char = cfg.tag_symbols[tag]
					custom_symbol_found = true
					break
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

	local days_per_row = 29
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
			cfg.birthday, years, months, days, M.days_lived, cfg.max_age * 365))
		table.insert(lines, "")
	elseif config.get().grid_mode == "year" and M.current_year_view then
		table.insert(lines, string.format("  Year: %d", M.current_year_view))
		table.insert(lines, "")
	elseif config.get().grid_mode == "calendar" then
		table.insert(lines, "")
	end

	local current_display_year = tonumber(os.date("%Y"))
	local relevant_periods = {}
	for _, period in ipairs(cfg.periods) do
		local duration = grid.period_duration_in_days(period)
		if grid.period_overlaps_year(period, current_display_year) then
			if M.filter_long_periods then
				if duration <= 300 then table.insert(relevant_periods, period) end
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
		else
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
		local date_str = day.date
		local cfg = config.get()
		local birthday = grid.parse_date(cfg.birthday)
		local current_date = grid.parse_date(date_str)
		local years, months, days = grid.age_detailed(birthday, current_date)

		local timestamp = grid.date_to_timestamp(current_date)
		local original_locale = os.setlocale(nil, "time")
		local weekday
		local success, result = pcall(function()
			os.setlocale(cfg.locale, "time")
			local day_name = os.date("%A", timestamp)
			os.setlocale(original_locale, "time")
			return day_name
		end)

		if success and result then
			weekday = result
		else
			os.setlocale("C", "time")
			weekday = os.date("%A", timestamp)
			os.setlocale(original_locale, "time")
		end

		local today_date_str = os.date("%Y-%m-%d")
		local today_parsed = grid.parse_date(today_date_str)
		local days_diff = grid.days_between(today_parsed, current_date)

		local days_diff_str
		if days_diff == 0 then
			days_diff_str = "Today"
		elseif days_diff > 0 then
			days_diff_str = string.format("+%d day%s", days_diff, days_diff == 1 and "" or "s")
		else
			days_diff_str = string.format("%d day%s", days_diff, days_diff == -1 and "" or "s")
		end

		local display_str = string.format(" %s  │  %s  │  %s  │  %dY %02dM %02dD", weekday, date_str, days_diff_str, years, months, days)

		local has_note = notes.note_exists(date_str)
		local meta = has_note and (notes.note_metadata[date_str] or {}) or (recurring.get_virtual_metadata(date_str) or {})

		local tag_parts = {}
		if meta.tags then
			local all_tags = type(meta.tags) == "string" and { meta.tags } or meta.tags
			for _, t in ipairs(all_tags) do table.insert(tag_parts, "#" .. t) end
		end

		if #tag_parts > 0 then
			display_str = display_str .. "  │  " .. table.concat(tag_parts, "  ")
		end

		if type(meta.title) == "string" and meta.title ~= "" then
			display_str = display_str .. "  │  " .. meta.title
		end

		vim.api.nvim_buf_set_lines(M.date_buf, 0, -1, false, { display_str })
	else
		if M.date_buf and vim.api.nvim_buf_is_valid(M.date_buf) then
			vim.api.nvim_buf_set_lines(M.date_buf, 0, -1, false, { "" })
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
	vim.api.nvim_buf_call(M.preview_buf, function()
		vim.cmd("lcd " .. vim.fn.fnameescape(cfg.daily_notes_path))
	end)

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
		col = 113 - margin
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
	if #M.note_win_ids == 0 then
		vim.api.nvim_command("rightbelow vsplit " .. vim.fn.fnameescape(filepath))
		table.insert(M.note_win_ids, vim.api.nvim_get_current_win())
		vim.api.nvim_set_current_win(current_grid_win)
	elseif #M.note_win_ids == 1 then
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

		local valid = {}
		for _, win_id in ipairs(M.note_win_ids) do
			if vim.api.nvim_win_is_valid(win_id) then table.insert(valid, win_id) end
		end
		M.note_win_ids = valid

if cfg.note_split_mode == "reuse" and #M.note_win_ids > 0 then
  local note_win_id = M.note_win_ids[1]
  -- alte Note speichern
  local old_buf = vim.api.nvim_win_get_buf(note_win_id)
  pcall(vim.api.nvim_buf_call, old_buf, function() vim.cmd("silent! write") end)
  -- neue Note laden
  local buf = vim.fn.bufnr(filepath, true)
  vim.api.nvim_win_set_buf(note_win_id, buf)
  vim.api.nvim_buf_call(buf, function() vim.cmd("edit") end)
  vim.api.nvim_set_current_win(current_grid_win)
		else
			local effective_split_strategy = M.split_strategy
			if not effective_split_strategy then
				effective_split_strategy = win_width <= vertical_split_threshold and "narrow" or "wide"
				M.split_strategy = effective_split_strategy
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
	vim.notify("Period colors " .. (M.periods_enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

local function toggle_period_filter()
	M.filter_long_periods = not M.filter_long_periods
	render_grid()
	vim.notify("Long period filter " .. (M.filter_long_periods and "enabled" or "disabled"), vim.log.levels.INFO)
end

local function close_all_note_splits()
	if #M.note_win_ids == 0 then
		vim.notify("No note splits to close.", vim.log.levels.INFO)
		return
	end
	local original_win = vim.api.nvim_get_current_win()
	local had_error = false
	local closed_count = 0
	local win_ids_copy = {}
	for _, id in ipairs(M.note_win_ids) do table.insert(win_ids_copy, id) end

	for _, win_id in ipairs(win_ids_copy) do
		if vim.api.nvim_win_is_valid(win_id) then
			local success, _ = pcall(vim.api.nvim_win_close, win_id, false)
			if success then
				closed_count = closed_count + 1
			else
				had_error = true
			end
		end
	end
	M.split_strategy = nil
	vim.api.nvim_set_current_win(original_win)
	if had_error then
		vim.notify("Could not close some splits (unsaved changes?).", vim.log.levels.WARN)
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
			vim.api.nvim_buf_call(buf_id, function() vim.cmd("write") end)
			vim.api.nvim_win_close(win_id, false)
			closed_count = closed_count + 1
		end
	end
	M.split_strategy = nil
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
	if #M.note_win_ids > 0 then close_all_note_splits() end
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

			local original_win = vim.api.nvim_get_current_win()
			local wins_to_close = {}
			for _, win_id in ipairs(M.note_win_ids) do
				if vim.api.nvim_win_is_valid(win_id) then
					local buf_id = vim.api.nvim_win_get_buf(win_id)
					if vim.api.nvim_buf_get_name(buf_id) == filepath then
						table.insert(wins_to_close, win_id)
					end
				end
			end

			for _, win_id in ipairs(wins_to_close) do
				vim.api.nvim_win_close(win_id, true)
			end
			local valid = {}
			for _, win_id in ipairs(M.note_win_ids) do
				if vim.api.nvim_win_is_valid(win_id) then table.insert(valid, win_id) end
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

local function open_tag_picker()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf    = require("telescope.config").values
	local actions = require("telescope.actions")
	local state   = require("telescope.actions.state")

	local today = os.date("%Y-%m-%d")
	local cfg   = config.get()

	local tracked = cfg.tracked_tags or { deadline = { label = "Deadlines", icon = "❗", order = 1 } }
	local tag_keys = vim.tbl_keys(tracked)
	table.sort(tag_keys, function(a, b)
		return (tracked[a].order or 99) < (tracked[b].order or 99)
	end)

	if #tag_keys == 0 then
		vim.notify("No tracked_tags configured.", vim.log.levels.WARN)
		return
	end

	local function build_items(tag, filter_state, year_filter)
		local items = {}
		for _, dl in ipairs(notes.get_tagged_notes(tag)) do
			local days_left = grid.days_between(grid.parse_date(today), grid.parse_date(dl.date))

			if year_filter then
				local item_year = dl.date:match("^(%d%d%d%d)")
				if tonumber(item_year) ~= tonumber(os.date("%Y")) then
					goto continue
				end
			end

			local is_valid = (filter_state == "all")
				or (filter_state == "expired" and days_left < 0)
				or (filter_state == "upcoming" and days_left >= 0)

			if is_valid then
				local status
				if days_left < 0 then status = "EXPIRED"
				elseif days_left <= 7 then status = "THIS WEEK"
				else status = "UPCOMING" end

				table.insert(items, {
					display   = string.format("%-10s  %-12s  %s (%+d days)", status, dl.date, dl.title, days_left),
					filepath  = cfg.daily_notes_path .. "/" .. dl.date .. ".md",
					date      = dl.date,
					days_left = days_left,
				})
			end
			::continue::
		end

		table.sort(items, function(a, b)
			if a.days_left < 0 and b.days_left >= 0 then return false end
			if a.days_left >= 0 and b.days_left < 0 then return true end
			return a.days_left < b.days_left
		end)
		return items
	end

	local function launch(idx, filter_state, year_filter)
		local tag     = tag_keys[idx]
		local tag_cfg = tracked[tag] or {}
		local icon    = tag_cfg.icon or ""
		local label   = tag_cfg.label or tag
		local next_state = filter_state == "upcoming" and "expired" or (filter_state == "expired" and "all" or "upcoming")

		local title = string.format("%s %s [%s]  <C-t>: tag  <C-e>: %s  <C-r>: range",
			icon, label,
			year_filter and os.date("%Y") or "all",
			filter_state)

		pickers.new({}, {
			prompt_title = title,
			finder = finders.new_table({
				results = build_items(tag, filter_state, year_filter),
				entry_maker = function(item)
					return { value = item, display = item.display, ordinal = item.display, path = item.filepath }
				end,
			}),
			previewer = conf.file_previewer({}),
			sorter    = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local sel = state.get_selected_entry()
					actions.close(prompt_bufnr)

					local filepath = sel.value.filepath
					local current_grid_win = M.win
					vim.api.nvim_set_current_win(current_grid_win)

					local valid = {}
					for _, win_id in ipairs(M.note_win_ids) do
						if vim.api.nvim_win_is_valid(win_id) then table.insert(valid, win_id) end
					end
					M.note_win_ids = valid

					local current_cfg = config.get()
					if current_cfg.note_split_mode == "reuse" and #M.note_win_ids > 0 then
						local buf = vim.fn.bufnr(filepath, true)
						vim.api.nvim_win_set_buf(M.note_win_ids[1], buf)
						vim.api.nvim_buf_call(buf, function() vim.cmd("edit") end)
						vim.api.nvim_set_current_win(M.note_win_ids[1])
					else
						local effective_split = M.split_strategy or (vim.api.nvim_win_get_width(current_grid_win) <= 120 and "narrow" or "wide")
						M.split_strategy = effective_split

						if effective_split == "narrow" then
							handle_narrow_split(filepath, current_grid_win)
						else
							handle_wide_split(filepath, current_grid_win)
						end
						vim.api.nvim_set_current_win(M.note_win_ids[#M.note_win_ids])
					end
				end)
				map("i", "<C-e>", function()
					actions.close(prompt_bufnr)
					launch(idx, next_state, year_filter)
				end)
				map("i", "<C-t>", function()
					actions.close(prompt_bufnr)
					launch((idx % #tag_keys) + 1, filter_state, year_filter)
				end)
				map("i", "<C-r>", function()
					actions.close(prompt_bufnr)
					launch(idx, filter_state, not year_filter)
				end)
				return true
			end,
		}):find()
	end

	launch(1, "upcoming", true)
end

local function setup_keymaps()
	local buf = M.buf
	local popts = { buffer = buf, noremap = true, silent = true }

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
				break
			end
		end
	end

	vim.keymap.set("n", "<Plug>(recollect-quit)", function() M.close() end, popts)

	vim.keymap.set("n", "<Plug>(recollect-recurring)", function()
		recurring.open({
			on_close = function()
				recurring.load()
				render_grid()
			end
		})
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-tag-picker)", open_tag_picker, popts)
	vim.keymap.set("n", "<Plug>(recollect-close-splits)", close_all_note_splits, popts)
	vim.keymap.set("n", "<Plug>(recollect-write-splits)", write_and_close_all_note_splits, popts)
	vim.keymap.set("n", "<Plug>(recollect-delete-note)", confirm_delete_note, popts)
	vim.keymap.set("n", "<Plug>(recollect-open-note)", open_note_split, popts)
	vim.keymap.set("n", "<Plug>(recollect-toggle-split)", toggle_note_split_mode, popts)
	vim.keymap.set("n", "<Plug>(recollect-today)", jump_to_today, popts)
	vim.keymap.set("n", "<Plug>(recollect-preview)", toggle_note_preview, popts)
	vim.keymap.set("n", "<Plug>(recollect-toggle-periods)", toggle_periods_display, popts)
	vim.keymap.set("n", "<Plug>(recollect-filter-periods)", toggle_period_filter, popts)

	vim.keymap.set("n", "<Plug>(recollect-refresh)", function()
		notes.build_cache()
		M.days, M.days_lived = grid.generate_life_days()
		render_grid()
		vim.notify("Recollect refreshed", vim.log.levels.INFO)
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-search-date)", function()
		vim.ui.input({ prompt = "Jump to date (YYYY-MM-DD): " }, function(input)
			if not input then return end
			input = input:gsub("%.", "-")
			for i, day in ipairs(M.days) do
				if day.date == input then
					for _, h in ipairs(M.current_highlights) do
						if h.day_idx == i then
							vim.api.nvim_win_set_cursor(M.win, { h.line + 1, h.col_start + 1 })
							vim.cmd("normal! zz")
							render_grid()
							if M.preview_enabled then show_note_preview() end
							vim.notify("Jumped to " .. input, vim.log.levels.INFO)
							return
						end
					end
				end
			end
			vim.notify("Date not found: " .. input, vim.log.levels.WARN)
		end)
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-toggle-grid)", function()
		local cfg = config.get()
		if cfg.grid_mode == "life" then
			cfg.grid_mode = "calendar"
			M.days, M.days_lived = grid.generate_calendar_years_days()
		else
			cfg.grid_mode = "life"
			M.days, M.days_lived = grid.generate_life_days()
		end
		render_grid()
		jump_to_today()
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-year-view)", function()
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
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-manage-periods)", function()
		periods.open({
			on_close = function()
				M.days, M.days_lived = grid.generate_life_days()
				render_grid()
				vim.notify("Recollect refreshed", vim.log.levels.INFO)
			end
		})
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-prev-note)", function()
		local current_idx = find_day_at_cursor() or 1
		for i = current_idx - 1, 1, -1 do
			if notes.note_exists(M.days[i].date) then
				for _, h in ipairs(M.current_highlights) do
					if h.day_idx == i then
						vim.api.nvim_win_set_cursor(M.win, { h.line + 1, h.col_start + 1 })
						vim.cmd("normal! zz")
						render_grid()
						if M.preview_enabled then show_note_preview() end
						vim.notify("Jumped to previous note: " .. M.days[i].date, vim.log.levels.INFO)
						return
					end
				end
			end
		end
		vim.notify("No previous note found", vim.log.levels.WARN)
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-next-note)", function()
		local current_idx = find_day_at_cursor() or 1
		for i = current_idx + 1, #M.days do
			if notes.note_exists(M.days[i].date) then
				for _, h in ipairs(M.current_highlights) do
					if h.day_idx == i then
						vim.api.nvim_win_set_cursor(M.win, { h.line + 1, h.col_start + 1 })
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
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-search-content)", function()
		local cfg = config.get()
		local current_win_width = vim.api.nvim_win_get_width(0)
		local vertical_preview_threshold = 120
		local previewer_config = {}
		if current_win_width > vertical_preview_threshold then
			previewer_config = {
				layout_strategy = "horizontal",
				layout_config = { horizontal = { width = 0.5, height = 0.8, preview_height = 0.7 } },
			}
		else
			previewer_config = {
				layout_strategy = "vertical",
				layout_config = { vertical = { width = 0.9, height = 0.9, preview_width = 0.7, preview_height = 0.7 } },
			}
		end
		require("telescope.builtin").live_grep({
			cwd = cfg.daily_notes_path,
			prompt_title = "Search Notes Content",
			layout_strategy = previewer_config.layout_strategy,
			layout_config = previewer_config.layout_config,
			attach_mappings = function(_, map)
				map("i", "<CR>", function(prompt_bufnr)
					local selection = require("telescope.actions.state").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)
					if selection then
						local filepath = selection.filename
						local date = filepath:match("(%d%d%d%d%-%d%d%-%d%d)%.md$")
						if date then
							for i, day in ipairs(M.days) do
								if day.date == date then
									for _, h in ipairs(M.current_highlights) do
										if h.day_idx == i then
											vim.api.nvim_win_set_cursor(M.win, { h.line + 1, h.col_start + 1 })
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
	end, popts)

	vim.keymap.set("n", "<Plug>(recollect-help)", function()
		local help_lines = {
			"  ╔═══════════════════════════════════════╗",
			"  ║           Recollect HELP              ║",
			"  ╚═══════════════════════════════════════╝",
			"",
			"  Navigation:",
			"    j/k/b/w       Move cursor",
			"    <C-d>/<C-u>   Scroll half page",
			"    t              Jump to today",
			"    /              Search date (YYYY-MM-DD)",
			"    [              Jump to previous note",
			"    ]              Jump to next note",
			"",
			"  Actions:",
			"    <Enter>        Open in split",
			"    D              Delete note",
			"    f              Fuzzy search notes content",
			"    r              Refresh cache",
			"    x              :q all splits",
			"    X              :wq all splits",
			"    m              Manage periods",
			"    E              Manage recurring events",
			"    T              Tag Picker",
			"",
			"  Toggles:",
			"    s              Toggle split behaviour",
			"    p              Toggle note preview",
			"    Y              Toggle year view",
			"    g              Toggle Calendar/Life grid",
			"    P              Toggle period colors",
			"    R              Toggle long period filter",
			"",
			"  Other:",
			"    q              Close Recollect",
			"    ?              Show this help",
			"",
			"  Press q or <Enter> to close...",
		}

		local help_buf = vim.api.nvim_create_buf(false, true)
		local help_win = vim.api.nvim_open_win(help_buf, true, {
			relative = "editor",
			width = 47,
			height = #help_lines,
			col = math.floor((vim.o.columns - 47) / 2),
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
	end, popts)

	-- Default key → <Plug> bindings
	local opts = { buffer = buf, remap = true, nowait = true, silent = true }

	vim.keymap.set("n", "q",     "<Plug>(recollect-quit)",            opts)
	vim.keymap.set("n", "x",     "<Plug>(recollect-close-splits)",    opts)
	vim.keymap.set("n", "X",     "<Plug>(recollect-write-splits)",    opts)
	vim.keymap.set("n", "D",     "<Plug>(recollect-delete-note)",     opts)
	vim.keymap.set("n", "<CR>",  "<Plug>(recollect-open-note)",       opts)
	vim.keymap.set("n", "s",     "<Plug>(recollect-toggle-split)",    opts)
	vim.keymap.set("n", "r",     "<Plug>(recollect-refresh)",         opts)
	vim.keymap.set("n", "t",     "<Plug>(recollect-today)",           opts)
	vim.keymap.set("n", "/",     "<Plug>(recollect-search-date)",     opts)
	vim.keymap.set("n", "p",     "<Plug>(recollect-preview)",         opts)
	vim.keymap.set("n", "P",     "<Plug>(recollect-toggle-periods)",  opts)
	vim.keymap.set("n", "R",     "<Plug>(recollect-filter-periods)",  opts)
	vim.keymap.set("n", "g",     "<Plug>(recollect-toggle-grid)",     opts)
	vim.keymap.set("n", "Y",     "<Plug>(recollect-year-view)",       opts)
	vim.keymap.set("n", "m",     "<Plug>(recollect-manage-periods)",  opts)
	vim.keymap.set("n", "E",     "<Plug>(recollect-recurring)",       opts)
	vim.keymap.set("n", "[",     "<Plug>(recollect-prev-note)",       opts)
	vim.keymap.set("n", "]",     "<Plug>(recollect-next-note)",       opts)
	vim.keymap.set("n", "f",     "<Plug>(recollect-search-content)",  opts)
	vim.keymap.set("n", "?",     "<Plug>(recollect-help)",            opts)
	vim.keymap.set("n", "T",     "<Plug>(recollect-tag-picker)",      opts)

	-- Pass-through movement keys
	vim.keymap.set("n", "j",     "j",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "k",     "k",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "h",     "h",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "l",     "l",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "b",     "b",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "w",     "w",     { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<C-d>", "<C-d>", { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<C-u>", "<C-u>", { buffer = buf, nowait = true, silent = true })
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
	vim.api.nvim_buf_set_option(M.date_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(M.date_buf, "bufhidden", "wipe")

	local bar_pos = cfg.bar_position or "top"
	local bar_offset = cfg.bar_offset or 0
	local bar_row = bar_pos == "bottom"
		and (vim.o.lines - 2 - bar_offset)
		or  (0 + bar_offset)

	M.date_win = vim.api.nvim_open_win(M.date_buf, false, {
		relative  = "editor",
		row       = bar_row,
		col       = 0,
		width     = vim.o.columns,
		height    = 1,
		style     = "minimal",
		border    = "none",
		focusable = false,
		zindex    = 50,
	})
	vim.api.nvim_win_set_option(M.date_win, "winhl", "Normal:recollectTopBar")

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = M.buf,
		callback = function()
			update_date_display()
			if M.preview_enabled then show_note_preview() end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			if M.date_win and vim.api.nvim_win_is_valid(M.date_win) then
				vim.api.nvim_win_set_config(M.date_win, { width = vim.o.columns })
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		callback = function(args)
			for i, win_id in ipairs(M.note_win_ids) do
				if tostring(win_id) == args.match then
					table.remove(M.note_win_ids, i)
					break
				end
			end
		end,
	})

	for i, day in ipairs(M.days) do
		if day.is_today then
			for _, h in ipairs(M.current_highlights) do
				if h.day_idx == i then
					vim.api.nvim_win_set_cursor(M.win, { math.max(1, h.line + 1), h.col_start + 1 })
					vim.cmd("normal! zz")
					break
				end
			end
			break
		end
	end
end

function M.close()
  if M.cursor_autocmd_id then
    pcall(vim.api.nvim_del_autocmd, M.cursor_autocmd_id)
    M.cursor_autocmd_id = nil
  end

  -- note splits speichern + schließen
  for _, win_id in ipairs(M.note_win_ids) do
    if vim.api.nvim_win_is_valid(win_id) then
      local buf_id = vim.api.nvim_win_get_buf(win_id)
      pcall(vim.api.nvim_buf_call, buf_id, function() vim.cmd("silent! write") end)
      pcall(vim.api.nvim_win_close, win_id, true)
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

  local win = M.win
  local buf = M.buf

  M.buf = nil
  M.win = nil
  M.preview_buf = nil
  M.preview_win = nil
  M.date_buf = nil
  M.date_win = nil
  M.preview_enabled = false
  M.note_win_ids = {}
  M.split_strategy = nil

  -- recollect buffer löschen, dann window aufräumen
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  vim.schedule(function()
    if win and vim.api.nvim_win_is_valid(win) then
      if #vim.api.nvim_list_wins() <= 1 then
        vim.cmd("quit")
      else
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)
end
return M
