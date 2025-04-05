return {
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "terraform-ls", "tflint" })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        terraformls = {
          filetypes = { "terraform", "terraform-vars", "hcl" },
          on_attach = function(client, bufnr)
            require("treesitter-terraform-doc").setup({
              command_name = "OpenDoc",
              url_opener_command = "!open",
              jump_argument = true,
            })
            local wk = require("which-key")
            wk.add({
              { "<leader>td", "<cmd>OpenDoc<CR>", desc = "Terraform Documentation", buffer = bufnr },
            })
          end,
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "terraform", "hcl" })
      end
    end,
  },
  {
    "Afourcat/treesitter-terraform-doc.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
  },
}
