#!/usr/bin/env python3
"""Infrastructure-as-code rule contracts for MicroTodoSuite.

Implements the automated checks that the rules in
microservice-app-ai-agents/rules/iac/ assign to a contract. Every finding names
the rule it enforces, so a failure points at the rule text that explains it.

Usage:
  contracts.py [--format text|json] module DIR [--config FILE]
  contracts.py [--format text|json] root DIR
  contracts.py [--format text|json] repo DIR --kind modules|live [--config FILE]
  contracts.py [--format text|json] plan FILE --client CODE --project CODE [--domain NAME]

`module` and `root` accept `--exceptions FILE` and `--repo-root DIR`; `repo`
reads `docs/iac-exceptions.md` and `iac-contracts.json` from the repository.

Exit status: 0 without findings, 1 with findings, 2 on a usage or parse error.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

try:
    import hcl2
except ImportError:
    sys.stderr.write("contracts.py needs python-hcl2: install scripts/iac/requirements.txt\n")
    sys.exit(2)


# PC-IAC-001 and PC-IAC-026: the files every module and its sample carry.
MODULE_FILES = (
    "README.md", "CHANGELOG.md", ".gitignore", "versions.tf", "providers.tf",
    "variables.tf", "locals.tf", "data.tf", "main.tf", "outputs.tf",
)
MODULE_TF_FILES = tuple(name for name in MODULE_FILES if name.endswith(".tf"))
SAMPLE_FILES = (
    "terraform.tfvars", "variables.tf", "data.tf", "locals.tf", "main.tf",
    "outputs.tf", "providers.tf", "README.md",
)

# PC-IAC-002: the governance inputs of every root and module.
GOVERNANCE_VARIABLES = ("client", "project", "environment")
# PC-IAC-002: inputs that identify or size infrastructure take no default.
IDENTIFYING_NAME = re.compile(
    r"(^|_)(name|names|id|ids|arn|arns|cidr|cidrs|size|sizes|count|region|"
    r"account_id|zone|zones|domain|instance_type|instance_types)$"
)
# PC-IAC-016: inputs whose name says they carry a secret.
SECRET_NAME = re.compile(r"(password|secret|token|webhook|private_key|api_key)")
# PC-IAC-003: HCL identifiers.
SNAKE_CASE = re.compile(r"^[a-z][a-z0-9_]*$")
# PC-IAC-007: what an output name ends in; the project adds the attribute kinds
# that EKS, networking, and endpoints return besides IDs, ARNs, and names.
OUTPUT_SUFFIXES = (
    "_id", "_ids", "_arn", "_arns", "_name", "_names", "_url", "_urls",
    "_endpoint", "_endpoints", "_cidr", "_cidrs", "_data", "_version",
)
BARE_REFERENCE = re.compile(
    r"^(module\.[a-z0-9_-]+|data\.[a-z0-9_]+\.[a-z0-9_]+|[a-z0-9]+_[a-z0-9_]+\.[a-z0-9_]+)$"
)
# PC-IAC-010: resource types whose loss is unrecoverable or an outage.
PROTECTED_TYPES = ("aws_route53_zone", "aws_ecr_repository", "azurerm_key_vault")
# PC-IAC-011: computational data sources allowed inside modules.
MODULE_DATA_SOURCES = (
    "aws_region", "aws_partition", "aws_caller_identity", "aws_iam_policy_document",
    "azurerm_client_config", "azurerm_subscription",
)
# PC-IAC-023: types a service module must receive rather than create.
FORBIDDEN_IN_MODULES = (
    "aws_iam_role", "aws_iam_policy", "aws_iam_role_policy",
    "aws_iam_role_policy_attachment", "aws_iam_instance_profile", "aws_iam_user",
    "aws_security_group", "aws_security_group_rule",
    "aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_egress_rule",
    "aws_vpc", "aws_subnet", "aws_route_table", "aws_route",
    "aws_route_table_association", "aws_internet_gateway", "aws_nat_gateway",
    "aws_lb", "aws_alb", "azurerm_virtual_network", "azurerm_subnet",
    "azurerm_network_security_group", "azurerm_role_assignment",
)
GOVERNANCE_REFERENCE = re.compile(r"var\.(client|project|environment)\b")
ACCOUNT_LITERAL = re.compile(r"(?<![0-9A-Za-z])[0-9]{12}(?![0-9A-Za-z])")
REGION_LITERAL = re.compile(r'"(us|eu|ap|sa|ca|me|af|il|mx)-(gov-)?[a-z]+-[0-9]"')
MODULE_TAG = re.compile(r"^(?P<module>[a-z0-9]+(?:-[a-z0-9]+)*)-v\d+\.\d+\.\d+$")
REGISTRY_SOURCE = re.compile(r"^[a-z0-9-]+/[a-z0-9-]+/[a-z0-9]+(//.*)?$")
EXACT_VERSION = re.compile(r"^=?\s*\d+\.\d+\.\d+$")
PATCH_RANGE = re.compile(r"^~>\s*\d+\.\d+\.\d+$")

ENVIRONMENTS = ("shd", "eco", "fdev", "fstg", "fprd")
# MTS-IAC-101: the type segment of each resource type's physical name.
TYPE_CODES = {
    "aws_vpc": ("vpc",), "aws_subnet": ("sub",), "aws_route_table": ("rtb",),
    "aws_internet_gateway": ("igw",), "aws_nat_gateway": ("nat",), "aws_eip": ("eip",),
    "aws_ec2_transit_gateway": ("tgw",), "aws_ec2_transit_gateway_vpc_attachment": ("tgwa",),
    "aws_vpc_endpoint": ("vpce",), "aws_flow_log": ("fl",), "aws_security_group": ("sg",),
    "aws_network_acl": ("nacl",), "aws_iam_role": ("role",), "aws_iam_policy": ("pol",),
    "aws_kms_key": ("kms",), "aws_kms_alias": ("kms",), "aws_s3_bucket": ("s3",),
    "aws_ecr_repository": ("ecr",), "aws_secretsmanager_secret": ("sm",),
    "aws_eks_cluster": ("eks",), "aws_eks_node_group": ("ng",), "aws_launch_template": ("lt",),
    "aws_cloudwatch_log_group": ("cwl",), "aws_sqs_queue": ("sqs",), "aws_lb": ("alb", "nlb"),
}
NAME_ATTRIBUTE = {"aws_s3_bucket": "bucket", "aws_eks_node_group": "node_group_name"}
PREFIX_ATTRIBUTE = {"aws_s3_bucket": "bucket_prefix", "aws_eks_node_group": "node_group_name_prefix"}
# MTS-IAC-101 exceptions: the physical name is set by the service.
SERVICE_NAMED = ("aws_route53_zone", "aws_iam_openid_connect_provider")
TRANSVERSAL_TAGS = ("Client", "Project", "Environment", "Owner", "CostCenter", "ManagedBy", "Repository")

# PC-IAC-022: resource types by domain. A type in no list is not judged.
GENERIC_PREFIXES = ("terraform_data", "null_resource", "random_", "time_", "tls_", "local_")
DOMAIN_RULES = {
    "security": (
        "aws_iam_", "aws_kms_", "aws_wafv2_", "aws_security_group", "aws_vpc_security_group_",
        "aws_network_acl", "aws_default_security_group", "aws_default_network_acl",
        "aws_secretsmanager_",
    ),
    "networking": (
        "=aws_vpc", "aws_vpc_endpoint", "aws_vpc_ipv4_cidr_block_association",
        "aws_vpc_dhcp_options", "=aws_subnet", "=aws_route", "aws_route_table",
        "aws_main_route_table_association", "=aws_internet_gateway",
        "aws_egress_only_internet_gateway", "=aws_nat_gateway", "=aws_eip",
        "aws_ec2_transit_gateway", "=aws_flow_log", "=aws_default_vpc",
        "=aws_default_route_table", "=aws_cloudwatch_log_group",
    ),
    "workload": (
        "aws_eks_", "=aws_launch_template", "aws_lb", "aws_alb", "=aws_cloudwatch_log_group",
        "aws_sqs_", "aws_cloudwatch_event_", "aws_s3_bucket", "=aws_route53_record",
        "aws_autoscaling_",
    ),
    "state": ("aws_s3_bucket", "=aws_kms_key", "=aws_kms_alias"),
    "registry": ("aws_ecr_",),
    "dns": ("aws_route53_",),
}


@dataclass
class Finding:
    rule: str
    path: str
    address: str
    message: str

    def text(self) -> str:
        where = f"{self.path} {self.address}" if self.address else self.path
        return f"FAIL {self.rule} {where}: {self.message}"


class ParseError(Exception):
    pass


# ---------------------------------------------------------------------------
# HCL access helpers. python-hcl2 keeps string literals quoted and wraps
# expressions in ${...}; these helpers compare them without the wrapping.

def unquote(value):
    if isinstance(value, str) and len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def expression(value):
    value = unquote(value)
    if isinstance(value, str) and value.startswith("${") and value.endswith("}"):
        return value[2:-1].strip()
    return value


def is_literal_string(value) -> bool:
    return isinstance(value, str) and value.startswith('"') and "${" not in value


def is_true(value) -> bool:
    return value is True or expression(value) in ("true", True)


LABEL_DEPTH = {"resource": 2, "data": 2, "variable": 1, "output": 1, "module": 1,
               "provider": 1, "check": 1, "backend": 1, "dynamic": 1}


def blocks(node: dict, kind: str):
    """Yield (labels, body) for every `kind` block directly inside node."""
    depth = LABEL_DEPTH.get(kind, 0)
    for entry in node.get(kind, []) or []:
        yield from _descend(entry, depth, ())


def _descend(node, depth, labels):
    if depth == 0:
        yield labels, node
        return
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        if key.startswith("__"):
            continue
        yield from _descend(value, depth - 1, labels + (unquote(key),))


def attributes(body: dict) -> dict:
    return {key: value for key, value in body.items() if not key.startswith("__")}


class Terraform:
    """The parsed .tf files of one directory."""

    def __init__(self, directory: Path):
        self.directory = directory
        self.files: dict[str, dict] = {}
        self.text: dict[str, str] = {}
        for path in sorted(directory.glob("*.tf")):
            raw = path.read_text(encoding="utf-8")
            self.text[path.name] = raw
            try:
                self.files[path.name] = hcl2.loads(raw) if raw.strip() else {}
            except Exception as error:  # the parser raises several types
                raise ParseError(f"{path}: {error}") from error

    def each(self, kind: str):
        for name, doc in self.files.items():
            for labels, body in blocks(doc, kind):
                yield name, labels, body

    def terraform_blocks(self):
        for name, doc in self.files.items():
            for _, body in blocks(doc, "terraform"):
                yield name, body

    def required_providers(self):
        for _, body in self.terraform_blocks():
            for _, providers in blocks(body, "required_providers"):
                for local_name, spec in attributes(providers).items():
                    if isinstance(spec, dict):
                        yield local_name, spec

    def backends(self):
        for name, body in self.terraform_blocks():
            for labels, backend in blocks(body, "backend"):
                yield name, labels[0] if labels else "", backend

    def variables(self):
        for name, labels, body in self.each("variable"):
            yield name, labels[0], body

    def resources(self):
        for name, labels, body in self.each("resource"):
            yield name, labels[0], labels[1], body


# ---------------------------------------------------------------------------
# Checks shared by modules and roots.

class Checker:
    def __init__(self, repo_root: Path | None, exceptions: list[dict]):
        self.repo_root = repo_root
        self.exceptions = exceptions
        self.findings: list[Finding] = []
        self.waived: list[Finding] = []
        self.checked = 0

    def display(self, path: Path) -> str:
        if self.repo_root is not None:
            try:
                return os.path.relpath(path, self.repo_root)
            except ValueError:
                pass
        return str(path)

    def add(self, rule: str, path: Path, address: str, message: str) -> None:
        finding = Finding(rule, self.display(path), address, message)
        for row in self.exceptions:
            if (row["rule"] == rule and _path_matches(finding.path, row["path"])
                    and row["resource"] in ("*", address)):
                self.waived.append(finding)
                return
        self.findings.append(finding)

    # -- PC-IAC-002 and PC-IAC-016 ------------------------------------------
    def check_variables(self, tf: Terraform, where: Path) -> None:
        declared = set()
        for _, name, body in tf.variables():
            declared.add(name)
            address = f"var.{name}"
            if not SNAKE_CASE.match(name):
                self.add("PC-IAC-003", where, address, "variable names must be snake_case")
            if "type" not in body:
                self.add("PC-IAC-002", where, address, "the variable declares no type")
            if not unquote(body.get("description", "")):
                self.add("PC-IAC-002", where, address, "the variable declares no description")
            type_text = str(expression(body.get("type", ""))).replace(" ", "")
            if type_text != "bool" and not body.get("validation"):
                self.add("PC-IAC-002", where, address,
                         "a non-boolean variable needs at least one validation block")
            if "default" in body and _identifies_or_sizes(name, type_text, body["default"]):
                self.add("PC-IAC-002", where, address,
                         "a variable that identifies or sizes infrastructure takes no default")
            if SECRET_NAME.search(name) and not is_true(body.get("sensitive")):
                self.add("PC-IAC-016", where, address,
                         "a variable whose name marks a secret must set sensitive = true")
        for name in GOVERNANCE_VARIABLES:
            if name not in declared:
                self.add("PC-IAC-002", where, f"var.{name}", "the governance variable is missing")

    # -- PC-IAC-007 -----------------------------------------------------------
    def check_outputs(self, tf: Terraform, where: Path) -> None:
        for _, labels, body in tf.each("output"):
            name = labels[0]
            address = f"output.{name}"
            if not unquote(body.get("description", "")):
                self.add("PC-IAC-007", where, address, "the output declares no description")
            if not SNAKE_CASE.match(name) or not name.endswith(OUTPUT_SUFFIXES):
                self.add("PC-IAC-007", where, address,
                         "output names are snake_case and end in what they return "
                         f"({', '.join(OUTPUT_SUFFIXES)})")
            value = expression(body.get("value", ""))
            if isinstance(value, str) and BARE_REFERENCE.match(value):
                self.add("PC-IAC-007", where, address,
                         "an output returns an attribute, never a whole resource or module")

    # -- PC-IAC-012 -----------------------------------------------------------
    def check_locals(self, tf: Terraform, where: Path) -> set[str]:
        names: set[str] = set()
        for filename, doc in tf.files.items():
            count = len(doc.get("locals", []) or [])
            if filename != "locals.tf" and count:
                self.add("PC-IAC-012", where, filename, "locals blocks belong only in locals.tf")
            if filename == "locals.tf" and count != 1:
                self.add("PC-IAC-012", where, filename,
                         f"locals.tf must contain exactly one locals block, found {count}")
            for _, body in blocks(doc, "locals"):
                for local in attributes(body):
                    names.add(local)
                    if not SNAKE_CASE.match(local):
                        self.add("PC-IAC-003", where, f"local.{local}", "local names must be snake_case")
        return names

    # -- PC-IAC-003 identifiers and PC-IAC-010 protection -------------------------
    def check_resources(self, tf: Terraform, where: Path, protected: tuple[str, ...]) -> None:
        for _, rtype, rname, body in tf.resources():
            address = f"{rtype}.{rname}"
            if not SNAKE_CASE.match(rname):
                self.add("PC-IAC-003", where, address, "resource names must be snake_case")
            if rtype in PROTECTED_TYPES or address in protected:
                lifecycle = next((b for _, b in blocks(body, "lifecycle")), {})
                if not is_true(lifecycle.get("prevent_destroy")):
                    self.add("PC-IAC-010", where, address,
                             "a protected resource needs lifecycle { prevent_destroy = true }")
        for _, labels, _ in tf.each("data"):
            if not SNAKE_CASE.match(labels[1]):
                self.add("PC-IAC-003", where, f"data.{labels[0]}.{labels[1]}",
                         "data source names must be snake_case")
        for _, labels, _ in tf.each("module"):
            if not SNAKE_CASE.match(labels[0]):
                self.add("PC-IAC-003", where, f"module.{labels[0]}", "module names must be snake_case")


def _identifies_or_sizes(name: str, type_text: str, default) -> bool:
    if IDENTIFYING_NAME.search(name):
        return True
    structured = type_text.startswith(("object(", "map(object(", "list(object(", "set(object("))
    empty = default in ({}, [], "${{}}", "${[]}")
    return structured and not empty


def _path_matches(path: str, prefix: str) -> bool:
    prefix = prefix.strip().rstrip("/")
    return path == prefix or path.startswith(prefix + "/")


def domain_allows(domain: str, rtype: str) -> bool:
    return any(_type_matches(rtype, rule) for rule in DOMAIN_RULES[domain])


def domains_of(rtype: str) -> list[str]:
    return [domain for domain in DOMAIN_RULES if domain_allows(domain, rtype)]


def _type_matches(rtype: str, rule: str) -> bool:
    return rtype == rule[1:] if rule.startswith("=") else rtype.startswith(rule)


# ---------------------------------------------------------------------------
# Modules.

def check_module(checker: Checker, directory: Path, config: dict) -> None:
    checker.checked += 1
    module_name = directory.name
    for required in MODULE_FILES:
        if not (directory / required).exists():
            checker.add("PC-IAC-001", directory, required, "the module lacks a required file")
    for path in sorted(directory.glob("*.tf")):
        if path.name not in MODULE_TF_FILES:
            checker.add("PC-IAC-001", directory, path.name,
                        "a module keeps its resources in the files PC-IAC-001 names")
    sample = directory / "sample"
    for required in SAMPLE_FILES:
        if not (sample / required).exists():
            checker.add("PC-IAC-001", directory, f"sample/{required}", "the sample lacks a required file")
    for required in MODULE_TF_FILES:
        _require_comment(checker, directory, directory / required, required)
    if not list((directory / "tests").glob("*.tftest.hcl")):
        checker.add("PC-IAC-018", directory, "tests/", "the module has no terraform test file")
    if (directory / ".terraform.lock.hcl").exists():
        checker.add("PC-IAC-006", directory, ".terraform.lock.hcl", "a module commits no lock file")

    tf = Terraform(directory)
    owned = set(config.get("module_owners", {}).get(module_name, []))
    protected = tuple(config.get("protected_resources", {}).get(module_name, []))

    checker.check_variables(tf, directory)
    checker.check_outputs(tf, directory)
    local_names = checker.check_locals(tf, directory)
    checker.check_resources(tf, directory, protected)

    resources = list(tf.resources())
    declared = {name for _, name, _ in tf.variables()}
    if resources and "additional_tags" not in declared:
        checker.add("PC-IAC-004", directory, "var.additional_tags",
                    "a module that creates resources accepts additional_tags")
    if resources and not any(name == "this" for _, _, name, _ in resources):
        checker.add("PC-IAC-003", directory, "", "the module's principal resource is named this")

    # PC-IAC-005: aliases received, never configured.
    for _, labels, _ in tf.each("provider"):
        checker.add("PC-IAC-005", directory, f"provider.{labels[0]}",
                    "a module declares no provider block; it receives aws.project")
    aliases = set()
    for local_name, spec in tf.required_providers():
        for alias in spec.get("configuration_aliases", []) or []:
            aliases.add(expression(alias))
        version = unquote(spec.get("version", ""))
        if not str(version).startswith(">="):
            checker.add("PC-IAC-006", directory, f"required_providers.{local_name}",
                        "a module declares a minimum provider version with >=")
    cloud_blocks = [(f"{t}.{n}", t, b) for _, t, n, b in resources]
    cloud_blocks += [(f"data.{labels[0]}.{labels[1]}", labels[0], body)
                     for _, labels, body in tf.each("data")]
    for address, rtype, body in cloud_blocks:
        cloud = rtype.split("_", 1)[0]
        if cloud not in ("aws", "azurerm"):
            continue
        expected = f"{cloud}.project"
        if expected not in aliases:
            checker.add("PC-IAC-005", directory, "versions.tf",
                        f"required_providers.{cloud} lists {expected} in configuration_aliases")
            aliases.add(expected)
        provider = expression(body.get("provider", ""))
        if provider not in aliases:
            checker.add("PC-IAC-005", directory, address, f"the block sets provider = {expected}")

    _check_required_version(checker, tf, directory)
    for filename, _, _ in tf.backends():
        checker.add("PC-IAC-008", directory, filename, "a module configures no backend")

    # PC-IAC-011: only computational data sources.
    for _, labels, _ in tf.each("data"):
        if labels[0] not in MODULE_DATA_SOURCES:
            checker.add("PC-IAC-011", directory, f"data.{labels[0]}.{labels[1]}",
                        "a module looks nothing up; the root passes the value in")

    # PC-IAC-023: types a service module receives rather than creates.
    for _, rtype, rname, _ in resources:
        if rtype in FORBIDDEN_IN_MODULES and rtype not in owned:
            checker.add("PC-IAC-023", directory, f"{rtype}.{rname}",
                        "a service module receives this resource as an input")

    # PC-IAC-025: names arrive built.
    for _, rtype, rname, body in resources:
        for attribute in _governance_attributes(body):
            checker.add("PC-IAC-025", directory, f"{rtype}.{rname}",
                        f"{attribute} is assembled from governance variables; the root builds names")
    for filename, doc in tf.files.items():
        for _, body in blocks(doc, "locals"):
            for local, value in attributes(body).items():
                if "tags" not in local and GOVERNANCE_REFERENCE.search(json.dumps(value, default=str)):
                    checker.add("PC-IAC-025", directory, f"local.{local}",
                                "only tag locals may use governance variables inside a module")
    del local_names

    check_sample(checker, directory, sample)


def check_sample(checker: Checker, directory: Path, sample: Path) -> None:
    main = sample / "main.tf"
    if not main.exists():
        return
    tf = Terraform(sample)
    doc = tf.files.get("main.tf", {})
    if doc.get("resource") or doc.get("locals"):
        checker.add("PC-IAC-026", directory, "sample/main.tf", "the sample's main.tf holds one module call only")
    calls = list(blocks(doc, "module"))
    if len(calls) != 1 or unquote(calls[0][1].get("source", "")) not in ("../", ".."):
        checker.add("PC-IAC-026", directory, "sample/main.tf",
                    'the sample calls the module exactly once with source = "../"')
    for filename, _, _ in tf.backends():
        checker.add("PC-IAC-026", directory, f"sample/{filename}", "the sample uses local state")


def _require_comment(checker: Checker, directory: Path, path: Path, label: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if not re.search(r"^\s*(#|//|/\*)", text, re.MULTILINE):
        checker.add("PC-IAC-001", directory, label, "every module file carries a descriptive comment")


def _governance_attributes(body, path=""):
    for key, value in attributes(body).items():
        if key in ("tags", "tags_all", "lifecycle", "provider"):
            continue
        here = f"{path}.{key}" if path else key
        if isinstance(value, dict):
            yield from _governance_attributes(value, here)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    yield from _governance_attributes(item, here)
                elif isinstance(item, str) and GOVERNANCE_REFERENCE.search(item):
                    yield here
        elif isinstance(value, str) and GOVERNANCE_REFERENCE.search(value):
            yield here


def _check_required_version(checker: Checker, tf: Terraform, where: Path) -> None:
    for _, body in tf.terraform_blocks():
        version = unquote(body.get("required_version", ""))
        if version and not str(version).startswith(">="):
            checker.add("PC-IAC-006", where, "terraform.required_version",
                        "required_version is a minimum declared with >=")


# ---------------------------------------------------------------------------
# Roots.

def check_root(checker: Checker, directory: Path) -> None:
    checker.checked += 1
    tf = Terraform(directory)
    checker.check_variables(tf, directory)
    checker.check_outputs(tf, directory)
    local_names = checker.check_locals(tf, directory)
    checker.check_resources(tf, directory, ())
    if "governance_prefix" not in local_names:
        checker.add("PC-IAC-012", directory, "local.governance_prefix",
                    "a root defines governance_prefix and derives every name from it")

    _check_required_version(checker, tf, directory)
    for local_name, spec in tf.required_providers():
        version = str(unquote(spec.get("version", ""))).strip()
        if not (EXACT_VERSION.match(version) or PATCH_RANGE.match(version)):
            checker.add("PC-IAC-006", directory, f"required_providers.{local_name}",
                        "a root pins each provider exactly or to a patch range (~> X.Y.Z)")
    if not (directory / ".terraform.lock.hcl").exists():
        checker.add("PC-IAC-006", directory, ".terraform.lock.hcl", "a root commits its lock file")

    backends = list(tf.backends())
    if not backends:
        checker.add("PC-IAC-008", directory, "terraform.backend", "a root declares a partial backend block")
    for filename, kind, body in backends:
        if kind not in ("s3", "azurerm"):
            checker.add("PC-IAC-008", directory, f"backend.{kind}", "AWS roots use s3 and Azure roots azurerm")
        if attributes(body):
            checker.add("PC-IAC-008", directory, f"backend.{kind}",
                        "the backend block is partial; values come from -backend-config")

    check_root_providers(checker, tf, directory)

    for _, labels, body in tf.each("module"):
        check_module_source(checker, directory, labels[0], body)

    for _, labels, _ in tf.each("data"):
        if labels[0] == "terraform_remote_state":
            checker.add("PC-IAC-017", directory, f"data.terraform_remote_state.{labels[1]}",
                        "terraform_remote_state needs a recorded exception (PC-IAC-019)")

    domain = directory.name
    if domain not in DOMAIN_RULES:
        checker.add("PC-IAC-022", directory, "", f"the root '{domain}' is not split by domain "
                    f"({', '.join(DOMAIN_RULES)})")
    else:
        for _, rtype, rname, _ in tf.resources():
            if rtype.startswith(GENERIC_PREFIXES) or domain_allows(domain, rtype):
                continue
            owners = domains_of(rtype)
            if owners:
                checker.add("PC-IAC-022", directory, f"{rtype}.{rname}",
                            f"a {domain} root does not create {owners[0]} resources")

    for filename, text in tf.text.items():
        for match in ACCOUNT_LITERAL.finditer(text):
            checker.add("MTS-IAC-103", directory, f"{filename}:{_line(text, match.start())}",
                        "an account ID arrives as var.aws_account_id, never as a literal")
        for match in REGION_LITERAL.finditer(text):
            checker.add("MTS-IAC-103", directory, f"{filename}:{_line(text, match.start())}",
                        "the region arrives from the environment's .tfvars, never as a literal")


def check_root_providers(checker: Checker, tf: Terraform, directory: Path) -> None:
    aws = [(labels, body) for _, labels, body in tf.each("provider") if labels[0] == "aws"]
    if not aws:
        return
    if not any(unquote(body.get("alias", "")) == "principal" for _, body in aws):
        checker.add("PC-IAC-005", directory, "provider.aws", 'the root configures the alias "principal"')
    for _, body in aws:
        alias = unquote(body.get("alias", "")) or "(default)"
        address = f"provider.aws.{alias}"
        if alias == "(default)":
            checker.add("PC-IAC-005", directory, address, "every root provider carries an alias")
        has_assume_role = bool(body.get("assume_role")) or any(
            labels and labels[0] == "assume_role" for labels, _ in blocks(body, "dynamic"))
        if not has_assume_role:
            checker.add("PC-IAC-005", directory, address, "the provider declares assume_role")
        if not body.get("default_tags"):
            checker.add("PC-IAC-004", directory, address, "the provider applies common_tags through default_tags")
        if "allowed_account_ids" not in body:
            checker.add("MTS-IAC-103", directory, address,
                        "the provider binds allowed_account_ids to var.aws_account_id")
        if is_literal_string(body.get("region")):
            checker.add("MTS-IAC-103", directory, address, "the region arrives as a variable")


def check_module_source(checker: Checker, directory: Path, name: str, body: dict) -> None:
    address = f"module.{name}"
    source = str(unquote(body.get("source", "")))
    if source.startswith(("./", "../")) or source in (".", ".."):
        checker.add("PC-IAC-015", directory, address, "a live root consumes modules remotely, never by local path")
        return
    if source.startswith(("git::", "github.com/")):
        path, _, query = source.partition("?")
        ref = dict(part.split("=", 1) for part in query.split("&") if "=" in part).get("ref")
        if not ref:
            checker.add("PC-IAC-015", directory, address, "a Git source pins ?ref= to a module tag")
            return
        tag = MODULE_TAG.match(ref)
        if not tag:
            checker.add("PC-IAC-015", directory, address,
                        f"ref '{ref}' is not a <module>-vX.Y.Z tag (MTS-IAC-102)")
            return
        subdirectory = path.split("//", 2)[-1].strip("/") if path.count("//") >= 2 else ""
        if subdirectory.split("/")[-1] != tag.group("module"):
            checker.add("PC-IAC-015", directory, address,
                        f"tag '{ref}' belongs to another module than '{subdirectory or '(root)'}'")
        return
    if REGISTRY_SOURCE.match(source):
        version = str(unquote(body.get("version", ""))).strip()
        if not EXACT_VERSION.match(version):
            checker.add("PC-IAC-015", directory, address, "a registry source pins an exact version")
        return
    checker.add("PC-IAC-015", directory, address, f"unsupported module source '{source}'")


def _line(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


# ---------------------------------------------------------------------------
# Repositories.

SKIPPED_DIRECTORIES = {"node_modules"}


def check_repo(checker: Checker, repo: Path, kind: str, config: dict) -> None:
    if kind == "modules":
        for directory in sorted(p for p in repo.iterdir() if p.is_dir()):
            if directory.name.startswith((".", "_")) or not list(directory.glob("*.tf")):
                continue
            check_module(checker, directory, config)
        return
    for current, dirnames, filenames in os.walk(repo):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d not in SKIPPED_DIRECTORIES)
        directory = Path(current)
        parts = directory.relative_to(repo).parts
        if "fixtures" in parts or not any(f.endswith(".tf") for f in filenames):
            continue
        if "modules" in parts:
            checker.add("MTS-IAC-102", directory, "",
                        "a live repository consumes modules by tag and holds no module")
            continue
        check_root(checker, directory)


def load_exceptions(path: Path | None) -> list[dict]:
    rows: list[dict] = []
    if path is None or not path.exists():
        return rows
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 5 or not re.match(r"^(PC|MTS)-IAC-\d{3}$", cells[0]):
            continue
        rule, where, resource, reason, expiry = cells[:5]
        if not expiry or not reason:
            sys.stderr.write(f"WARN {path}:{number}: an exception without a reason and an expiry waives nothing\n")
            continue
        rows.append({"rule": rule, "path": where.strip("`"), "resource": resource.strip("`") or "*"})
    return rows


# ---------------------------------------------------------------------------
# Plans.

def check_plan(checker: Checker, plan_path: Path, client: str, project: str, domain: str | None) -> None:
    checker.checked += 1
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    pattern = re.compile(
        rf"^{re.escape(client)}-{re.escape(project)}-(?P<env>{'|'.join(ENVIRONMENTS)})"
        r"-(?P<type>[a-z0-9]+)-(?P<key>[a-z0-9]{1,10})$"
    )

    def conforming(name, codes):
        if not isinstance(name, str):
            return None, "the name is not a string"
        if len(name) > 28:
            return None, f"'{name}' is longer than 28 characters"
        match = pattern.match(name)
        if not match:
            return None, f"'{name}' does not follow {client}-{project}-<environment>-<type>-<key>"
        if codes and match.group("type") not in codes:
            return None, f"'{name}' uses type '{match.group('type')}', expected {'/'.join(codes)}"
        return match, None

    for change in plan.get("resource_changes", []):
        if change.get("mode") != "managed":
            continue
        actions = change.get("change", {}).get("actions", [])
        after = change.get("change", {}).get("after")
        unknown = change.get("change", {}).get("after_unknown") or {}
        if after is None or actions == ["delete"]:
            continue
        rtype, address = change["type"], change["address"]

        if domain and not rtype.startswith(GENERIC_PREFIXES) and not domain_allows(domain, rtype):
            owners = domains_of(rtype)
            checker.add("PC-IAC-022", plan_path, address,
                        f"a {domain} root does not create {owners[0] if owners else rtype} resources")

        tags = after.get("tags_all") if isinstance(after.get("tags_all"), dict) else None
        name_tag = (tags or {}).get("Name") or (after.get("tags") or {}).get("Name")
        codes = TYPE_CODES.get(rtype)
        name_key = NAME_ATTRIBUTE.get(rtype, "name")
        prefix_key = PREFIX_ATTRIBUTE.get(rtype, "name_prefix")
        physical = after.get(name_key) if rtype not in SERVICE_NAMED else None
        expected_tag = physical
        name_match = None

        if after.get(prefix_key):
            checker.add("PC-IAC-003", plan_path, address,
                        f"{prefix_key} generates a name; set {name_key} to the built name")
        elif codes and name_key in after and physical is None and unknown.get(name_key):
            checker.add("PC-IAC-003", plan_path, address, f"{name_key} is generated at apply time")
        elif isinstance(physical, str):
            if rtype == "aws_s3_bucket" and re.search(r"-[0-9]{12}$", physical):
                expected_tag = physical[:-13]
                name_match, error = conforming(expected_tag, codes)
            elif rtype == "aws_kms_alias":
                expected_tag = physical.removeprefix("alias/")
                name_match, error = conforming(expected_tag, codes)
            elif rtype == "aws_cloudwatch_log_group" and physical.startswith("/"):
                expected_tag = None
                inner = re.match(r"^/aws/[a-z0-9-]+/(?P<inner>[a-z0-9-]+)(/[A-Za-z0-9_.-]+)*$", physical)
                name_match, error = conforming(inner.group("inner"), None) if inner else (
                    None, f"'{physical}' is neither a standard name nor /aws/<service>/<standard-name>")
            else:
                name_match, error = conforming(physical, codes)
            if error:
                checker.add("PC-IAC-003", plan_path, address, error)

        if name_tag is not None:
            tag_match, error = conforming(name_tag, codes)
            if error:
                checker.add("PC-IAC-003", plan_path, address, f"Name tag: {error}")
            name_match = name_match or tag_match
            if expected_tag is not None and isinstance(expected_tag, str) and name_tag != expected_tag:
                checker.add("PC-IAC-004", plan_path, address,
                            f"the Name tag '{name_tag}' differs from the name '{expected_tag}'")

        if tags is None or unknown.get("tags_all") is True:
            continue
        missing = [key for key in TRANSVERSAL_TAGS if key not in tags]
        if missing:
            checker.add("PC-IAC-004", plan_path, address, f"missing transversal tags: {', '.join(missing)}")
        if tags.get("Client", client) != client or tags.get("Project", project) != project:
            checker.add("PC-IAC-004", plan_path, address, "the Client or Project tag contradicts the codes")
        if name_match and "Environment" in tags and tags["Environment"] != name_match.group("env"):
            checker.add("PC-IAC-004", plan_path, address,
                        f"the Environment tag '{tags['Environment']}' contradicts the name")


# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--format", choices=("text", "json"), default="text")
    commands = parser.add_subparsers(dest="command", required=True)

    module = commands.add_parser("module")
    module.add_argument("directory", type=Path)
    module.add_argument("--config", type=Path)
    root = commands.add_parser("root")
    root.add_argument("directory", type=Path)
    for sub in (module, root):
        sub.add_argument("--exceptions", type=Path)
        sub.add_argument("--repo-root", type=Path)
    repo = commands.add_parser("repo")
    repo.add_argument("directory", type=Path)
    repo.add_argument("--kind", choices=("modules", "live"), required=True)
    repo.add_argument("--config", type=Path)
    plan = commands.add_parser("plan")
    plan.add_argument("file", type=Path)
    plan.add_argument("--client", required=True)
    plan.add_argument("--project", required=True)
    plan.add_argument("--domain", choices=tuple(DOMAIN_RULES))

    args = parser.parse_args(argv)
    try:
        if args.command == "repo":
            repo_root = args.directory.resolve()
            config_path = args.config or repo_root / "iac-contracts.json"
            checker = Checker(repo_root, load_exceptions(repo_root / "docs" / "iac-exceptions.md"))
            check_repo(checker, repo_root, args.kind, _load_config(config_path))
        elif args.command == "plan":
            checker = Checker(None, [])
            check_plan(checker, args.file, args.client, args.project, args.domain)
        else:
            directory = args.directory.resolve()
            repo_root = args.repo_root.resolve() if args.repo_root else None
            checker = Checker(repo_root, load_exceptions(args.exceptions))
            if args.command == "module":
                check_module(checker, directory, _load_config(args.config))
            else:
                check_root(checker, directory)
    except (ParseError, json.JSONDecodeError, OSError) as error:
        sys.stderr.write(f"ERROR {error}\n")
        return 2

    if args.format == "json":
        print(json.dumps({
            "checked": checker.checked,
            "findings": [asdict(f) for f in checker.findings],
            "waived": [asdict(f) for f in checker.waived],
        }, indent=2))
    else:
        for finding in checker.findings:
            print(finding.text())
        for finding in checker.waived:
            print(f"WAIVED {finding.rule} {finding.path} {finding.address}".rstrip())
        print(f"iac-contracts: {len(checker.findings)} finding(s), {len(checker.waived)} waived, "
              f"{checker.checked} unit(s) checked")
    return 1 if checker.findings else 0


def _load_config(path: Path | None) -> dict:
    if path is None or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
