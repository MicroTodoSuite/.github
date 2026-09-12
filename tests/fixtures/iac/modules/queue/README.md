# queue

Test fixture for the infrastructure-as-code contracts: a minimal module that
satisfies every module rule. It creates one encrypted SQS queue whose name the
consuming root builds.

## Inputs

| Name | Type | Description |
| --- | --- | --- |
| `client`, `project`, `environment` | `string` | Governance codes, used for tags |
| `queue` | `object` | Queue name and message retention |
| `additional_tags` | `map(string)` | Extra tags |

## Outputs

`queue_arn`, `queue_url`, `queue_name`.

## Example

See `sample/`.
