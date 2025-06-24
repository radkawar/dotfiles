## Claude MCP Servers

```bash
# project = local
# user = global

## AWS Labs - Documentation
claude mcp add aws-documentation -s user -e FASTMCP_LOG_LEVEL=ERROR -e AWS_DOCUMENTATION_PARTITION=aws -- uvx awslabs.aws-documentation-mcp-server@latest

## AWS Labs - Terraform
claude mcp add terraform -s user -e FASTMCP_LOG_LEVEL=ERROR -- uvx awslabs.terraform-mcp-server@latest

## AWS Labs - CloudFormation
claude mcp add cfn-server -s user -e AWS_PROFILE=your-profile-name -- uvx awslabs.cfn-mcp-server@latest

```
