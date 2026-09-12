# Default tflint configuration of the iac-checks workflow. A repository that
# needs different rules commits its own .tflint.hcl at the checked directory.

config {
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# PC-IAC-002 and PC-IAC-007: every variable and output is typed and documented.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

# PC-IAC-003: snake_case identifiers.
rule "terraform_naming_convention" {
  enabled = true
}

# PC-IAC-001 places variables and outputs in their own files.
rule "terraform_standard_module_structure" {
  enabled = true
}
