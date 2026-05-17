local M = {}

function M.check()
	vim.health.start("recollect.nvim")

	if pcall(require, "plenary") then
		vim.health.ok("plenary.nvim installed")
	else
		vim.health.error("plenary.nvim not installed (required dependency)")
	end

	if vim.fn.isdirectory(vim.fn.expand("~/Documents/dailies")) == 1 then
		vim.health.ok("~/Documents/dailies")
	else
		vim.health.warn("~/Documents/dailies does not exist (daily_notes_path)")
	end

	if vim.fn.isdirectory(vim.fn.expand("~/Documents/recollect-data")) == 1 then
		vim.health.ok("~/Documents/recollect-data")
	else
		vim.health.info("~/Documents/recollect-data will be auto-created on first use")
	end
end

return M
