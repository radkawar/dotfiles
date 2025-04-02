return {
  -- Add tokyonight plugin
  { "folke/tokyonight.nvim" },

  -- Configure LazyVim to load tokyonight colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },

  -- Configure tokyonight with options
  {
    "folke/tokyonight.nvim",
    config = function()
      require("tokyonight").setup({
        style = "storm", -- Options: "storm", "moon", "night", "day"
        transparent = false, -- Set to true for transparent background
        dim_inactive = false, -- Dim inactive windows
        styles = {
          comments = { italic = true },
          keywords = { bold = true },
        },
      })
      vim.cmd("colorscheme tokyonight")
    end,
  },
}
