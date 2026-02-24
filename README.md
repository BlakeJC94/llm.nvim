# LLM Plugin for Neovim

A Neovim plugin that integrates the [llm](https://llm.datasette.io/)
command-line tool for AI-powered text generation directly into your editor.

## Features

* **Asynchronous execution** - Run LLM commands without blocking your editor
* **Synchronous mode** - Insert LLM output directly at cursor position with `!`
bang
* **Visual selection support** - Send selected text as input to the LLM
* **Dedicated output window** - View LLM responses in a persistent split window
* **Progress indicator** - Animated feedback while waiting for responses
* **Vim modifiers support** - Use `%`, `%:p`, and other filename modifiers in
commands
* **Smart output formatting** - Automatically formats output with comment
strings when inserting into code files

## Prerequisites

You must have the [llm CLI tool](https://llm.datasette.io/) installed and configured:

```bash
uv tool install llm
# or pipx install llm
```

Refer to their docs for more information

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    {
        "https://github.com/BlakeJC94/llm.nvim",
        opts = {
            split = {
                direction = "horizontal",
                size = 14,
                position = "bottom",
            },
        },
        commands = {
            "LLM",
            "LLMToggle",
            "LLMOpen",
            "LLMClose",
            "LLMStop",
        },
        -- Optional: set keymaps
        keys = {
            {
                "<Leader>s",
                ":LLM ",
                mode = {"n", "v"},
            },
            {
                "<Leader>S",
                ":LLMToggle<CR>",
                mode = "n",
            },

    },
}
```

## Commands

### `:LLM {args}`

Execute an LLM command asynchronously and display output in the LLM window.

```vim
:LLM "Explain this code" < %
:LLM "Write a function to reverse a string"
:'<,'>LLM "Refactor this code"
```

### `:LLM! {args}`

Execute an LLM command synchronously and insert output at the cursor position.
Output is automatically wrapped in comments based on the current filetype.

```vim
:LLM! "Add error handling"
:'<,'>LLM! "Add JSDoc comments"
```

### `:LLMToggle`

Toggle the LLM output window open/closed.

### `:LLMOpen`

Open the LLM output window.

### `:LLMClose`

Close the LLM output window.

### `:LLMStop`

Stop the currently running LLM command.

## Configuration

The plugin can be configured during setup:

```lua
opts = {
    split = {
        direction = "horizontal",   -- or "vertical"
        size = 16,                  -- window size in lines/columns
        position = "bottom",        -- "bottom", "top", "left", or "right"
    },
    wo = {
        -- Window options for the LLM window
        wrap = true,
        number = false,
        relativenumber = false,
        cursorline = false,
        cursorcolumn = false,
        signcolumn = "no",
        spell = false,
    },
    bo = {
        -- Buffer options for the LLM buffer
        buflisted = false,
        filetype = "markdown",
    },
})
```

## Usage Examples

### Ask a question about current file

```vim
:LLM "Explain what this file does" < %
```

### Continue from last conversation

```vim
:LLM -c "Explain this part in more detail"
```

### Refactor selected code

Select code in visual mode, then:

```vim
:'<,'>LLM "Refactor this to be more efficient"
```

### Generate code at cursor

```vim
:LLM! "Write a function that validates email addresses"
```

### Print the last response (requires jq)

```vim
:LLM logs -n 1 --json | jq -r '.[].response'
```

### Add documentation to selection

Select a function, then:

```vim
:'<,'>LLM! "Add comprehensive docstrings and comments"
```

The output will be automatically formatted as comments based on your filetype.

## License

MIT
