# The principal AWS provider of the root, bound to the declared account.
provider "aws" {
  alias               = "principal"
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  dynamic "assume_role" {
    for_each = var.deploy_role_arn == "" ? [] : [var.deploy_role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
