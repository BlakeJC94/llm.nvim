--- LLM plugin for Neovim
--- Provides integration with the llm command-line tool for AI-powered text generation
local M = {}

--- Plugin state management
--- @class State
--- @field buf number|nil Buffer handle for the LLM output window
--- @field job_id table|nil System job handle for the running LLM process
--- @field win number|nil Window handle for the LLM output window
--- @field progress_timer number|nil Timer handle for progress indicator
--- @field awaiting_response boolean Whether an LLM request is currently in progress
--- @field n_dots_progress number Current number of dots to display in progress indicator (0-3)
local state = {
    buf = nil,
    job_id = nil,
    win = nil,
    progress_timer = nil,
    awaiting_response = false,
    n_dots_progress = 0,
}

--- Default plugin configuration
--- @class Config
--- @field split table Split window configuration
--- @field wo table Window options to apply to the LLM window
--- @field bo table Buffer options to apply to the LLM buffer
local CONFIG = {
    split = {
        direction = "horizontal",
        size = 16,
        position = "bottom",
    },
    wo = {
        cursorcolumn = false,
        cursorline = false,
        number = false,
        relativenumber = false,
        signcolumn = "no",
        spell = false,
        wrap = true,
    },
    bo = {
        buflisted = false,
        filetype = "markdown",
    },
}

--- Recursively evaluate configuration options
--- If an option is a function, call it to get the value
--- If an option is a table, recursively evaluate all values in the table
--- @param opts any Configuration option (can be a value, function, or table)
--- @return any Evaluated configuration value
local function eval_opts(opts)
    if type(opts) == "function" then
        return opts()
    end
    if type(opts) == "table" then
        local res = {}
        for k, v in pairs(opts) do
            res[k] = eval_opts(v)
        end
        return res
    end
    return opts
end

--- Generate the vim split command string based on configuration
--- @param config Config Configuration object containing split settings
--- @return string Vim split command (e.g., "botright 16split")
local function get_split_cmd(config)
    local opts = eval_opts(config.split)
    local pos = (opts.position == "left" or opts.position == "top") and "topleft" or "botright"
    local dir = opts.direction == "vertical" and " vertical" or ""
    return pos .. dir .. " " .. opts.size .. "split"
end

--- Create and configure a new window for the LLM buffer
--- @param config Config Configuration object containing window settings
--- @param buf number Buffer handle to display in the window
--- @return number Window handle of the created window
local function create_win(config, buf)
    vim.cmd(get_split_cmd(config))
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    for opt, val in pairs(config.wo) do
        vim.wo[win][opt] = val
    end
    return win
end

--- Check if the LLM window is currently open and valid
--- @return boolean True if the window exists and is valid, false otherwise
local function is_open()
    if state.win == nil then
        return false
    elseif vim.api.nvim_win_is_valid(state.win) then
        return true
    else
        return false
    end
end

--- Initialize or reset the LLM buffer
--- Creates a new buffer if none exists, or clears the existing buffer
--- Sets up buffer options and an autocmd to clean up state on buffer deletion
local function init_buffer()
    local buf_ready = state.buf and vim.api.nvim_buf_is_valid(state.buf)

    if not buf_ready then
        state.buf = vim.api.nvim_create_buf(false, true)
        for opt, val in pairs(CONFIG.bo) do
            vim.bo[state.buf][opt] = val
        end

        vim.api.nvim_buf_set_name(state.buf, "LLM")

        vim.api.nvim_create_autocmd("BufDelete", {
            buffer = state.buf,
            once = true,
            callback = function()
                state.buf = nil
                state.job_id = nil
                state.win = nil
            end,
        })
    else
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, true, {})
    end
end

--- Open the LLM output window
--- Creates and displays the LLM buffer in a split window
--- Returns focus to the previous window after opening
M.open = function()
    if is_open() then
        return
    end

    init_buffer()

    local prev_win = vim.api.nvim_get_current_win()
    state.win = create_win(CONFIG, state.buf)

    if vim.api.nvim_win_is_valid(prev_win) then
        vim.api.nvim_set_current_win(prev_win)
    end
end

--- Close the LLM output window
--- Closes the window but preserves the buffer for later use
M.close = function()
    if state.win == nil then
        return
    end
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
end

--- Toggle the LLM output window
--- Opens the window if closed, closes it if open
--- Creates the buffer if it doesn't exist
M.toggle = function()
    if not is_open() then
        M.open()
    else
        M.close()
    end
end

--- Progress indicator callback
--- Displays an animated "In progress..." message with cycling dots
--- Recursively schedules itself every 1 second while awaiting response
--- Internal function, not intended for direct use
M._cb_progress_print = function()
    if not state.awaiting_response then
        vim.fn.timer_stop(state.progress_timer)
        state.progress_timer = nil
        return
    end

    state.n_dots_progress = state.n_dots_progress % 3 + 1

    local msg = "In progress" .. string.rep(".", state.n_dots_progress)
    vim.api.nvim_buf_set_lines(state.buf, -2, -1, true, { msg })

    state.progress_timer = vim.fn.timer_start(1000, M._cb_progress_print)
end

--- Callback executed when the LLM job completes
--- Updates the buffer with the result or error message
--- @param obj table System job result object with code, stdout, and stderr
local cb_on_exit = function(obj)
    state.awaiting_response = false
    state.job_id = nil

    if not obj then
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(state.buf, -2, -1, true, { "Error: No response" })
        end)
        return
    end

    if obj.code > 0 then
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(state.buf, -2, -1, true, { "Aborted" })
        end)
        return
    end

    vim.schedule(function()
        vim.api.nvim_buf_set_lines(state.buf, -2, -1, true, vim.split(obj.stdout, "\n"))
    end)
end

--- Execute an LLM command
--- Supports both synchronous (with bang) and asynchronous execution
--- Can process visual selections and expand vim filename modifiers (%, %:p, etc.)
--- @param cmd_opts table Command options from user command
---   - bang: boolean - If true, execute synchronously and insert at cursor
---   - args: string - Arguments to pass to the llm command
---   - range: number - Number of lines in visual selection (0 if none)
---   - line1: number - Start line of visual selection
---   - line2: number - End line of visual selection
M.llm = function(cmd_opts)
    local bang = cmd_opts.bang
    local args = cmd_opts.args

    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= "" then
        args = args:gsub("()%%%S*", function(pos)
            if pos > 1 and args:sub(pos - 1, pos - 1) == "\\" then
                return nil
            end
            return vim.fn.expand(args:sub(pos))
        end)
    end

    local cmd_to_exec = "llm" .. " " .. args

    -- Check if we are in visual mode and get the selection range
    local text = nil
    if cmd_opts.range > 0 then
        local start_pos = math.min(cmd_opts.line1, cmd_opts.line2)
        local end_pos = math.max(cmd_opts.line1, cmd_opts.line2)
        local lines = vim.api.nvim_buf_get_lines(0, start_pos - 1, end_pos, false)

        if #lines >= 1 then
            text = table.concat(lines, "\n")
        end
    end

    init_buffer()

    local job_opts = {
        text = true,
    }
    if text then
        job_opts.stdin = text
    end

    if bang then
        -- synchronous exec, write output to cursor
        print("In progress...")
        local obj = vim.system({ "sh", "-c", cmd_to_exec }, job_opts):wait()

        if obj.code ~= nil and obj.code > 0 then
            vim.notify("llm failed: " .. obj.stderr, vim.log.levels.ERROR)
            return
        end

        local output_lines = vim.fn.split("\n" .. obj.stdout, "\n")

        local ft = vim.opt_local.filetype:get()
        if ft ~= "markdown" and ft ~= "" then
            local commentstring = vim.opt_local.commentstring:get()
            for i, _ in ipairs(output_lines) do
                output_lines[i] = string.format(commentstring, output_lines[i])
            end
        end
        vim.fn.append(vim.fn.line("."), output_lines)
        print("")
    else
        -- async exec
        if not is_open() then
            M.open()
        end

        state.job_id = vim.system({ "sh", "-c", cmd_to_exec }, job_opts, cb_on_exit)

        state.awaiting_response = true
        state.progress_timer = vim.fn.timer_start(0, M._cb_progress_print)
    end
end

--- Stop the currently running LLM job
--- Terminates the running process if one exists
M.stop = function()
    if state.job_id ~= nil then
        state.job_id:kill()
    end
end

--- Setup the LLM plugin
--- Initializes the plugin with user configuration and creates user commands
--- @param opts Config|nil Optional configuration table to override defaults
---   - split: table - Split window configuration (direction, size, position)
---   - wo: table - Window options for the LLM window
---   - bo: table - Buffer options for the LLM buffer
---
--- Creates the following user commands:
---   - :LLM {args} - Execute LLM command asynchronously in output window
---   - :LLM! {args} - Execute LLM command synchronously and insert at cursor
---   - :LLMStop - Stop the currently running LLM job
---   - :LLMToggle - Toggle the LLM output window
---   - :LLMOpen - Open the LLM output window
---   - :LLMClose - Close the LLM output window
M.setup = function(opts)
    CONFIG = vim.tbl_deep_extend("force", CONFIG, opts or {})

    local commands = {
        {
            name = "LLM",
            fn = M.llm,
            opts = { range = true, bang = true, nargs = "+", desc = "Invoke LLM Command" },
        },
        {
            name = "LLMStop",
            fn = M.stop,
            opts = { desc = "Interupt running LLM command" },
        },
        {
            name = "LLMToggle",
            fn = M.toggle,
            opts = { desc = "Toggle LLM Buffer" },
        },
        {
            name = "LLMOpen",
            fn = M.open,
            opts = { desc = "Open LLM Buffer" },
        },
        {
            name = "LLMClose",
            fn = M.close,
            opts = { desc = "Close LLM Buffer" },
        },
    }

    for _, cmd in ipairs(commands) do
        vim.api.nvim_create_user_command(cmd.name, cmd.fn, cmd.opts)
    end
end

return M
