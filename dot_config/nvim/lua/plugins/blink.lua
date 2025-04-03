return {
  "saghen/blink.cmp",
  opts = function(_, opts)
    opts.keymap = opts.keymap or {}
    opts.keymap.preset = nil -- Disable default preset to avoid conflicts
    opts.keymap["<Tab>"] = { "select_next", "snippet_forward", "fallback" }
    opts.keymap["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" }
    opts.keymap["<CR>"] = { "select_and_accept", "fallback" } -- Ensure Enter accepts
    return opts
  end,
}
