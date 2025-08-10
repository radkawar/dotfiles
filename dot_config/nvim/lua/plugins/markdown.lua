return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = {
          on_attach = function(client, bufnr)
            -- Disable diagnostics for markdown files
            vim.diagnostic.enable(false, { bufnr = bufnr })
            -- Disable spell checking for markdown files
            vim.opt_local.spell = false
          end,
        },
      },
    },
  },
}