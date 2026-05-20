require("plenary.busted")

local eq = assert.are.same

describe("recollect", function()
  before_each(function()
    package.loaded["recollect.config"] = nil
    package.loaded["recollect.config.defaults"] = nil
    package.loaded["recollect"] = nil
  end)

  it("loads without errors", function()
    local recollect = require("recollect")
    assert.is_not_nil(recollect)
    assert.is_not_nil(recollect.version)
  end)

  it("has a version string", function()
    local recollect = require("recollect")
    assert.is_string(recollect.version)
  end)

  it("exposes the public API", function()
    local recollect = require("recollect")
    assert.is_function(recollect.setup)
    assert.is_function(recollect.open)
    assert.is_function(recollect.close)
    assert.is_function(recollect.create_daily_note)
    assert.is_function(recollect.jump_to_date)
    assert.is_function(recollect.get_config)
  end)
end)

describe("recollect config", function()
  before_each(function()
    package.loaded["recollect.config"] = nil
    package.loaded["recollect.config.defaults"] = nil
    package.loaded["recollect"] = nil
  end)

  it("has sensible defaults", function()
    local cfg = require("recollect.config")
    local c = cfg.get()
    assert.is_table(c)
    assert.equals("1990-01-01", c.birthday)
    assert.equals(95, c.max_age)
    assert.equals("life", c.grid_mode)
    assert.equals("top", c.bar_position)
    assert.is_table(c.tag_symbols)
    assert.is_table(c.colors)
    assert.is_function(c.note_template)
  end)

  it("merges user options", function()
    local cfg = require("recollect.config")
    cfg.set({ birthday = "2000-06-15", max_age = 80 })
    local c = cfg.get()
    assert.equals("2000-06-15", c.birthday)
    assert.equals(80, c.max_age)
    assert.equals("life", c.grid_mode)
  end)

  it("deep copies defaults so they stay intact", function()
    local cfg = require("recollect.config")
    cfg.set({ birthday = "1970-03-20" })
    local c = cfg.get()
    assert.equals("1970-03-20", c.birthday)

    package.loaded["recollect.config"] = nil
    package.loaded["recollect.config.defaults"] = nil

    local cfg2 = require("recollect.config")
    local d = cfg2.get()
    assert.equals("1990-01-01", d.birthday)
  end)
end)

describe("recollect grid", function()
  before_each(function()
    package.loaded["recollect.config"] = nil
    package.loaded["recollect.config.defaults"] = nil
    package.loaded["recollect.grid"] = nil
  end)

  it("parses dates correctly", function()
    local grid = require("recollect.grid")
    local d = grid.parse_date("2025-05-20")
    assert.equals(2025, d.year)
    assert.equals(5, d.month)
    assert.equals(20, d.day)
  end)

  it("calculates days between dates", function()
    local grid = require("recollect.grid")
    local d1 = { year = 2025, month = 1, day = 1 }
    local d2 = { year = 2025, month = 1, day = 3 }
    assert.equals(2, grid.days_between(d1, d2))
  end)

  it("calculates age at date", function()
    local grid = require("recollect.grid")
    local birthday = { year = 1990, month = 6, day = 15 }
    local target = { year = 2025, month = 6, day = 15 }
    assert.equals(35, grid.age_at_date(birthday, target))
  end)

  it("calculates age at date before birthday in a year", function()
    local grid = require("recollect.grid")
    local birthday = { year = 1990, month = 6, day = 15 }
    local target = { year = 2025, month = 1, day = 1 }
    assert.equals(34, grid.age_at_date(birthday, target))
  end)

  it("generates life days", function()
    local grid = require("recollect.grid")
    local days, lived = grid.generate_life_days()
    assert.is_table(days)
    assert.is_number(lived)
    assert.is_true(#days > 0)
    local first = days[1]
    assert.equals("1990-01-01", first.date)
    assert.equals(0, first.age)
  end)

  it("date from offset works", function()
    local grid = require("recollect.grid")
    local result = grid.date_from_offset("1990-01-01", 0)
    assert.equals("1990-01-01", result)
    local result2 = grid.date_from_offset("1990-01-01", 1)
    assert.equals("1990-01-02", result2)
  end)

  it("period overlaps year detection", function()
    local grid = require("recollect.grid")
    local period = { start = "2020-01-01", finish = "2022-12-31" }
    assert.is_true(grid.period_overlaps_year(period, 2021))
    assert.is_false(grid.period_overlaps_year(period, 2019))
    assert.is_false(grid.period_overlaps_year(period, 2023))
  end)
end)
