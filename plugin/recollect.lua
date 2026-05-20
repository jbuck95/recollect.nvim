if vim.g.loaded_recollect then return end
vim.g.loaded_recollect = true

vim.api.nvim_create_user_command("Recollect", function(args)
  local sub = vim.trim(args.args)
  if sub == "" or sub == "open" then
    require("recollect").open()
  elseif sub == "today" then
    require("recollect").create_daily_note()
  elseif sub == "periods" then
    require("recollect.periods").open()
  elseif sub == "recurring" then
    require("recollect.recurring").open()
  else
    vim.notify("Recollect: unknown subcommand '" .. sub .. "'. Try: open, today, periods, recurring", vim.log.levels.WARN)
  end
end, {
  nargs = "?",
  desc = "Recollect: life-grid daily notes",
  complete = function(arglead)
    local subcommands = { "open", "today", "periods", "recurring" }
    local matches = {}
    for _, sc in ipairs(subcommands) do
      if sc:find("^" .. vim.pesc(arglead)) then
        matches[#matches + 1] = sc
      end
    end
    return matches
  end,
})
