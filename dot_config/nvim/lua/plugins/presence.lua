return {
  "andweeb/presence.nvim",
  event = "VeryLazy",
  config = function()
    require("presence").setup({
      neovim_image_text = "hello there",
    })
  end,
}
