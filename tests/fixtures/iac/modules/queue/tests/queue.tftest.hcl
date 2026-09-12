# Plan-time tests of the queue module against a mocked AWS provider.
mock_provider "aws" {
  alias = "project"
}

variables {
  client      = "lex"
  project     = "mts"
  environment = "fdev"
  queue = {
    name                      = "lex-mts-fdev-sqs-events"
    message_retention_seconds = 345600
  }
}

run "creates_the_named_queue" {
  command = plan

  providers = {
    aws.project = aws.project
  }

  assert {
    condition     = aws_sqs_queue.this.name == "lex-mts-fdev-sqs-events"
    error_message = "The queue must carry the name the root built."
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Name"] == "lex-mts-fdev-sqs-events"
    error_message = "The Name tag must equal the queue name."
  }
}

run "rejects_an_unknown_environment" {
  command = plan

  providers = {
    aws.project = aws.project
  }

  variables {
    environment = "dev"
  }

  expect_failures = [var.environment]
}
