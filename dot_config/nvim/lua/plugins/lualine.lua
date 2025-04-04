return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = function(_, opts)
    -- Remove time section
    opts.sections.lualine_z = {}

    -- Minimize visual height by adjusting separators and padding
    opts.options = {
      component_separators = { left = "", right = "" }, -- Remove separators to reduce visual bulk
      section_separators = { left = "", right = "" },
      globalstatus = true, -- Use a single statusline (avoids duplication if set to false)
      theme = "tokyonight", -- Ensure lualine uses Tokyo Night theme
    }

    return opts
  end,
}
