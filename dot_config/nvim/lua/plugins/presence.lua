return {
  "andweeb/presence.nvim",
  event = "VeryLazy",
  config = function()
    require("presence").setup({
      neovim_image_text = "neovim",
      show_time = false,
      enable_line_number = true,
    })
  end,
}
