---@class recollect.Notes
---@field note_cache     table<string, boolean>
---@field note_metadata  table<string, table>
local M = {}
local config = require("recollect.config")

M.note_cache = {}
M.note_metadata = {}

---@param filepath string
---@return table
local function parse_frontmatter(filepath)
  local file = io.open(filepath, "r")
  if not file then return {} end

  local content = file:read("*all")
  file:close()

  local frontmatter = {}
  local fm_pattern = "^%-%-%-\r?\n(.-)\r?\n%-%-%-"
  local fm_match = content:match(fm_pattern)

  if fm_match then
    local current_key = nil
    for line in fm_match:gmatch("[^\r\n]+") do
      local key, value = line:match("^(%w+):%s*(.*)$")
      if key then
        current_key = key
        value = value:gsub('^["\']', ''):gsub('["\']$', '')
        if value == "" then
          frontmatter[current_key] = {}
        else
          if value:match("^%[.*%]$") then
            frontmatter[current_key] = {}
            for item in value:gmatch("([^,%s%[%]]+)") do
              table.insert(frontmatter[current_key], item)
            end
          else
            frontmatter[current_key] = value
          end
        end
      else
        local item = line:match("^%s*-%s*(.+)$")
        if item and current_key and type(frontmatter[current_key]) == "table" then
          item = item:gsub('^["\']', ''):gsub('["\']$', '')
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

---Scan the daily_notes_path for YYYY-MM-DD.md files and populate caches.
function M.build_cache()
  local scan = require("plenary.scandir")
  local cfg = config.get()
  M.note_cache = {}
  M.note_metadata = {}

  local notes_dir = cfg.daily_notes_path
  if vim.fn.isdirectory(notes_dir) == 0 then
    vim.fn.mkdir(notes_dir, "p")
    return
  end

  local files = scan.scan_dir(notes_dir, {
    hidden = false,
    depth = 1,
    search_pattern = "%.md$"
  })

  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    if filename:match("^%d%d%d%d%-%d%d%-%d%d$") then
      M.note_cache[filename] = true
      M.note_metadata[filename] = parse_frontmatter(filepath)
    end
  end
end

---Check whether a daily note exists for the given date.
---@param date_str string  YYYY-MM-DD
---@return boolean
function M.note_exists(date_str)
  if not next(M.note_cache) then
    M.build_cache()
  end
  return M.note_cache[date_str] == true
end

---Get metadata for a date, merging real file frontmatter with recurring virtual metadata.
---@param date_str string  YYYY-MM-DD
---@return table|nil
function M.get_metadata(date_str)
  local recurring = require("recollect.recurring")
  if not next(M.note_metadata) then
    M.build_cache()
  end
  local meta = vim.deepcopy(M.note_metadata[date_str] or {})

  local virt = recurring.get_virtual_metadata(date_str)
  if virt then
    if not meta.tags then
      meta.tags = virt.tags
    else
      local existing = type(meta.tags) == "string" and { meta.tags } or meta.tags
      for _, t in ipairs(virt.tags) do
        table.insert(existing, t)
      end
      meta.tags = existing
    end
    if not meta.title then meta.title = virt.title end
    meta._recurring = true
  end

  return meta
end

---Create the daily note file (with template) if it doesn't exist, then open it.
---@param date_str string  YYYY-MM-DD
function M.open_or_create(date_str)
  local cfg = config.get()
  local filepath = cfg.daily_notes_path .. "/" .. date_str .. ".md"

  if vim.fn.isdirectory(cfg.daily_notes_path) == 0 then
    vim.fn.mkdir(cfg.daily_notes_path, "p")
  end

  if vim.fn.filereadable(filepath) == 0 then
    local file = io.open(filepath, "w")
    if file then
      local template = cfg.note_template(date_str)
      file:write(template)
      file:close()
    end
  end

  vim.cmd("edit " .. filepath)
  M.build_cache()
end

---Create (or open) today's daily note.
function M.create_today()
  local today = os.date("%Y-%m-%d")
  M.open_or_create(today)
end

---Delete a daily note file.
---@param date_str string  YYYY-MM-DD
---@return boolean  True if the note was deleted
function M.delete_note(date_str)
  local cfg = config.get()
  local filepath = cfg.daily_notes_path .. "/" .. date_str .. ".md"

  if vim.fn.filereadable(filepath) == 1 then
    vim.fn.delete(filepath)
    M.build_cache()
    return true
  end
  return false
end

---Get all notes tagged with a specific tag.
---@param tag string
---@return {date: string, deadline: string, title: string}[]
function M.get_tagged_notes(tag)
  if not next(M.note_metadata) then M.build_cache() end
  local results = {}
  for date_str, meta in pairs(M.note_metadata) do
    local tags = meta.tags
    if type(tags) == "string" then tags = { tags } end
    if type(tags) == "table" then
      for _, t in ipairs(tags) do
        if t == tag then
          table.insert(results, {
            date     = date_str,
            deadline = meta.deadline or date_str,
            title    = meta.title or "Kein Titel",
          })
          break
        end
      end
    end
  end
  return results
end

---@deprecated Use get_tagged_notes("deadline") instead.
function M.get_deadlines()
  return M.get_tagged_notes("deadline")
end

return M
