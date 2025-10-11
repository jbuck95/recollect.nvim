-- ~/.config/nvim/lua/recollect/notes.lua
local M = {}
local config = require("recollect.config")
local scan = require("plenary.scandir")

-- Cache for note existence
M.note_cache = {}
M.note_metadata = {} -- Store frontmatter data

-- Parse frontmatter from note
local function parse_frontmatter(filepath)
  local file = io.open(filepath, "r")
  if not file then return {} end

  local content = file:read("*all")
  file:close()

  local frontmatter = {}
  -- Handle both \n and \r\n line endings, and potential whitespace after ---
  local fm_pattern = "^%-%-%-\r?\n(.-)\r?\n%-%-%-"
  local fm_match = content:match(fm_pattern)

  if fm_match then
    local current_key = nil
    for line in fm_match:gmatch("[^\r\n]+") do
      -- Check for a new key
      local key, value = line:match("^(%w+):%s*(.*)$")
      if key then
        current_key = key
        value = value:gsub('^["\']', ''):gsub('["\']$', '') -- remove quotes

        if value == "" then -- It's a list
          frontmatter[current_key] = {}
        else -- It's a single value or an inline list
          if value:match("^%[.*%]$") then -- inline list: [one, two]
            frontmatter[current_key] = {}
            for item in value:gmatch("([^,%s%[%]]+)") do
              table.insert(frontmatter[current_key], item)
            end
          else -- single value
            frontmatter[current_key] = value
          end
        end
      else
        -- Check for a list item for the current key
        local item = line:match("^%s*-%s*(.+)$")
        if item and current_key and type(frontmatter[current_key]) == "table" then
          item = item:gsub('^["\']', ''):gsub('["\']$', '') -- remove quotes
          table.insert(frontmatter[current_key], item)
        end
      end
    end
  end

  return frontmatter
end

function M.clear_cache()
  M.note_cache = {}
  M.note_metadata = {}
end

-- Build note cache
function M.build_cache()
  local cfg = config.get()
  M.note_cache = {}
  M.note_metadata = {}
  
  -- Ensure directory exists
  local notes_dir = cfg.daily_notes_path
  if vim.fn.isdirectory(notes_dir) == 0 then
    vim.fn.mkdir(notes_dir, "p")
    return
  end
  
  -- Scan for markdown files
  local files = scan.scan_dir(notes_dir, {
    hidden = false,
    depth = 1,
    search_pattern = "%.md$"
  })
  
  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    -- Check if filename matches date format (YYYY-MM-DD)
    if filename:match("^%d%d%d%d%-%d%d%-%d%d$") then
      M.note_cache[filename] = true
      M.note_metadata[filename] = parse_frontmatter(filepath)
    end
  end
end

-- Check if note exists for date
function M.note_exists(date_str)
  if not next(M.note_cache) then
    M.build_cache()
  end
  return M.note_cache[date_str] == true
end

-- Get note metadata
function M.get_metadata(date_str)
  if not next(M.note_metadata) then
    M.build_cache()
  end
  return M.note_metadata[date_str] or {}
end

-- Create or open daily note
function M.open_or_create(date_str)
  local cfg = config.get()
  local filepath = cfg.daily_notes_path .. "/" .. date_str .. ".md"
  
  -- Create directory if needed
  if vim.fn.isdirectory(cfg.daily_notes_path) == 0 then
    vim.fn.mkdir(cfg.daily_notes_path, "p")
  end
  
  -- Create file with template if it doesn't exist
  if vim.fn.filereadable(filepath) == 0 then
    local file = io.open(filepath, "w")
    if file then
      local template = cfg.note_template(date_str)
      file:write(template)
      file:close()
    end
  end

  -- Open in current window
  vim.cmd("edit " .. filepath)
  
  -- Rebuild cache
  M.build_cache()
end

-- Create today's note
function M.create_today()
  local today = os.date("%Y-%m-%d")
  M.open_or_create(today)
end
-- Delete a daily note
function M.delete_note(date_str)
  local cfg = config.get()
  local filepath = cfg.daily_notes_path .. "/" .. date_str .. ".md"

  if vim.fn.filereadable(filepath) == 1 then
    vim.fn.delete(filepath)
    M.build_cache() -- Rebuild cache after deletion
    return true
  end
  return false
end

return M
