---@class recollect.Grid
---@field parse_date             fun(date_str: string): recollect.DateParts
---@field date_to_timestamp      fun(date: recollect.DateParts): number
---@field days_between           fun(date1: recollect.DateParts, date2: recollect.DateParts): number
---@field age_at_date            fun(birthday: recollect.DateParts, target_date: recollect.DateParts): number
---@field age_detailed           fun(birthdate: recollect.DateParts, current_date: recollect.DateParts): number, number, number
---@field period_overlaps_year   fun(period: recollect.Period, year: number): boolean
---@field period_duration_in_days fun(period: recollect.Period): number
---@field date_from_offset       fun(birthday_str: string, offset_days: number): string
---@field generate_life_days     fun(): recollect.GridDay[], number
---@field generate_year_days     fun(year: number): recollect.GridDay[], number
---@field generate_calendar_years_days fun(): recollect.GridDay[], number

---@class recollect.DateParts
---@field year   number
---@field month  number
---@field day    number

---@class recollect.GridDay
---@field date         string   YYYY-MM-DD
---@field age          number?
---@field year         number
---@field is_today     boolean?
---@field is_past      boolean?
---@field is_future    boolean?
---@field is_pre_birth boolean?
---@field period_color string?
---@field period_label string?
---@field row          number
---@field col          number

local M = {}
local config = require("recollect.config")

function M.parse_date(date_str)
  local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
  return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

function M.date_to_timestamp(date)
  return os.time({ year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 })
end

function M.days_between(date1, date2)
  local t1 = M.date_to_timestamp(date1)
  local t2 = M.date_to_timestamp(date2)
  return math.floor((t2 - t1) / 86400)
end

function M.age_at_date(birthday, target_date)
  local age = target_date.year - birthday.year
  if target_date.month < birthday.month or
     (target_date.month == birthday.month and target_date.day < birthday.day) then
    age = age - 1
  end
  return age
end

function M.age_detailed(birthdate, current_date)
  local years = current_date.year - birthdate.year
  local months = current_date.month - birthdate.month
  local days = current_date.day - birthdate.day

  if days < 0 then
    months = months - 1
    local prev_month = current_date.month - 1
    local prev_year = current_date.year
    if prev_month == 0 then
      prev_month = 12
      prev_year = prev_year - 1
    end
    local days_in_prev_month = os.date("*t", os.time({year=prev_year, month=prev_month+1, day=0})).day
    days = days + days_in_prev_month
  end

  if months < 0 then
    years = years - 1
    months = months + 12
  end

  return years, months, days
end

function M.period_overlaps_year(period, year)
  local start_date = M.parse_date(period.start)
  local finish_str = period.finish == "present" and os.date("%Y-%m-%d") or period.finish
  local finish_date = M.parse_date(finish_str)

  return (start_date.year <= year and finish_date.year >= year)
end

function M.period_duration_in_days(period)
  local start_date = M.parse_date(period.start)
  local finish_str = period.finish == "present" and os.date("%Y-%m-%d") or period.finish
  local finish_date = M.parse_date(finish_str)
  return M.days_between(start_date, finish_date)
end

function M.date_from_offset(birthday_str, offset_days)
  local birthday = M.parse_date(birthday_str)
  local timestamp = M.date_to_timestamp(birthday) + (offset_days * 86400)
  local date = os.date("*t", timestamp)
  return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

function M.generate_life_days()
  local cfg = config.get()
  local birthday = M.parse_date(cfg.birthday)
  local today = os.date("*t")
  local today_parsed = { year = today.year, month = today.month, day = today.day }

  local total_days = cfg.max_age * 365
  local days_lived_count = M.days_between(birthday, today_parsed) + 1

  local days = {}
  for i = 0, total_days - 1 do
    local date_str = M.date_from_offset(cfg.birthday, i)
    local date = M.parse_date(date_str)
    local age = M.age_at_date(birthday, date)
    local is_today = (date_str == os.date("%Y-%m-%d"))
    local is_past = M.days_between(birthday, date) < M.days_between(birthday, today_parsed)
    local is_future = M.days_between(birthday, date) > M.days_between(birthday, today_parsed)

    local period_color = nil
    local period_label = nil
    for _, period in ipairs(cfg.periods) do
      local start = M.parse_date(period.start)
      local finish_str = period.finish == "present" and os.date("%Y-%m-%d") or period.finish
      local finish = M.parse_date(finish_str)
      if M.days_between(start, date) >= 0 and M.days_between(date, finish) >= 0 then
        period_color = period.color
        period_label = period.label
        break
      end
    end

    table.insert(days, {
      date = date_str,
      age = age,
      year = date.year,
      is_today = is_today,
      is_past = is_past,
      is_future = is_future,
      period_color = period_color,
      period_label = period_label,
      row = math.floor(i / 52),
      col = i % 52,
    })
  end

  return days, days_lived_count
end

function M.generate_year_days(year)
  local cfg = config.get()
  local birthday = M.parse_date(cfg.birthday)
  local today = os.date("*t")
  local today_parsed = { year = today.year, month = today.month, day = today.day }

  local days = {}
  local start_date = { year = year, month = 1, day = 1 }
  local start_timestamp = M.date_to_timestamp(start_date)
  local days_in_year = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 366 or 365

  for i = 0, days_in_year - 1 do
    local timestamp = start_timestamp + (i * 86400)
    local date = os.date("*t", timestamp)
    local date_str = string.format("%04d-%02d-%02d", date.year, date.month, date.day)
    local age = M.age_at_date(birthday, date)
    local is_today = (date_str == os.date("%Y-%m-%d"))
    local is_past = M.date_to_timestamp(date) < M.date_to_timestamp(today_parsed)
    local is_future = M.date_to_timestamp(date) > M.date_to_timestamp(today_parsed)

    local period_color = nil
    local period_label = nil
    for _, period in ipairs(cfg.periods) do
      local start = M.parse_date(period.start)
      local finish_str = period.finish == "present" and os.date("%Y-%m-%d") or period.finish
      local finish = M.parse_date(finish_str)
      if M.days_between(start, date) >= 0 and M.days_between(date, finish) >= 0 then
        period_color = period.color
        period_label = period.label
        break
      end
    end

    table.insert(days, {
      date = date_str,
      age = age,
      year = date.year,
      is_today = is_today,
      is_past = is_past,
      is_future = is_future,
      period_color = period_color,
      period_label = period_label,
      row = math.floor(i / 52),
      col = i % 52,
    })
  end

  return days, 0
end

function M.generate_calendar_years_days()
  local cfg = config.get()
  local birthday = M.parse_date(cfg.birthday)
  local today = os.date("*t")
  local today_parsed = { year = today.year, month = today.month, day = today.day }
  local birthday_timestamp = M.date_to_timestamp(birthday)

  local days = {}

  for year = birthday.year, birthday.year + cfg.max_age do
    local days_in_year = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 366 or 365
    local year_start_date = { year = year, month = 1, day = 1 }
    local year_start_timestamp = M.date_to_timestamp(year_start_date)

    for i = 0, days_in_year - 1 do
      local timestamp = year_start_timestamp + (i * 86400)
      local date = os.date("*t", timestamp)
      local date_str = string.format("%04d-%02d-%02d", date.year, date.month, date.day)

      if timestamp < birthday_timestamp then
        table.insert(days, {
          date = date_str,
          year = date.year,
          is_pre_birth = true,
          row = (year - birthday.year) * 8 + math.floor(i / 52),
          col = i % 52,
        })
      else
        local age = M.age_at_date(birthday, date)
        local is_today = (date_str == os.date("%Y-%m-%d"))
        local is_past = timestamp < M.date_to_timestamp(today_parsed)
        local is_future = timestamp > M.date_to_timestamp(today_parsed)

        local period_color = nil
        local period_label = nil
        for _, period in ipairs(cfg.periods) do
          local start = M.parse_date(period.start)
          local finish_str = period.finish == "present" and os.date("%Y-%m-%d") or period.finish
          local finish = M.parse_date(finish_str)
          if M.days_between(start, date) >= 0 and M.days_between(date, finish) >= 0 then
            period_color = period.color
            period_label = period.label
            break
          end
        end

        table.insert(days, {
          date = date_str,
          age = age,
          year = date.year,
          is_today = is_today,
          is_past = is_past,
          is_future = is_future,
          period_color = period_color,
          period_label = period_label,
          is_pre_birth = false,
          row = (year - birthday.year) * 8 + math.floor(i / 52),
          col = i % 52,
        })
      end
    end
  end
  local days_lived_count = M.days_between(birthday, today_parsed) + 1
  return days, days_lived_count
end

return M
