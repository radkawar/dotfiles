return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = function(_, opts)
    -- Remove time
    opts.sections.lualine_z = {}
    return opts
  end,
}
