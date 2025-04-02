return {
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    keys = {
      {
        "<leader>gg",
        function()
          require("neogit").open()
        end,
        desc = "Open Neogit",
      },
    },
    dependencies = {
      "nvim-lua/plenary.nvim", -- Required
      "sindrets/diffview.nvim", -- Enables diffview integration
    },
    opts = {
      integrations = {
        diffview = true, -- Show diffs with Diffview
      },
    },
  },

  -- 📄 Diffview (Visual Git diff)
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Git Diff View" },
      { "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Close Diff View" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History (Current File)" },
    },
    config = true,
  },
}
