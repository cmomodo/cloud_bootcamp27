# Cloud Custodian Policies — Bastion Host

This folder contains starter Cloud Custodian policies to govern an AWS bastion host. Policies target EC2 instances and security groups identified by the tag `Role=bastion` (adjust as needed).

## What’s included
- Close public SSH on bastion security groups
- Require basic tags (`Owner`, `Environment`)
- Stop bastions after hours (offhours)
- Encrypt unencrypted EBS volumes on bastions
- Notify if a bastion has a public IP

See `bastion.yml` for details.

## Prerequisites
- Python 3.8+ and `pip` (or Docker)
- IAM permissions for your execution identity (CLI or Lambda) that cover at least:
  - `ec2:Describe*`, `ec2:StopInstances`, `ec2:CreateTags`, `ec2:CreateVolume`, `ec2:CreateSnapshot`, `ec2:AttachVolume`, `ec2:DetachVolume`, `ec2:ModifyInstanceAttribute`, `ec2:RevokeSecurityGroupIngress`
  - `sns:Publish` to your notifications topic (if using notify)
- AWS credentials configured (e.g., `~/.aws/credentials`, environment variables, or an assumed role)

## Install Custodian
- Using pipx (recommended): `pipx install c7n`
- Or pip: `pip install c7n`
- Docker alternative: `docker run --rm -it -v "$PWD:$PWD" -w "$PWD" cloudcustodian/c7n` (prepend this to commands below)

## Validate and Dry Run
- Validate policy syntax:
  - `custodian validate cloudcustodian/bastion.yml`
- Dry run in a region to see matched resources and actions (no changes):
  - `custodian run -s cloudcustodian/out -r us-east-1 --dryrun cloudcustodian/bastion.yml`

## Apply Changes
- Execute for real (be careful and ideally test in a non-prod account first):
  - `custodian run -s cloudcustodian/out -r us-east-1 cloudcustodian/bastion.yml`
- Review outputs under `cloudcustodian/out` (resources.json, metrics, logs)

## Identifying Your Bastion
- Default selector: instances and security groups with `tag:Role = bastion`.
- Alternatives (edit `bastion.yml` accordingly):
  - Match by Name: `tag:Name` contains `bastion`.
  - Limit to a CloudFormation stack: filter `tag:aws:cloudformation:stack-name` equals your stack name.

## Notifications
- Update the SNS topic ARN in `ec2-bastion-has-public-ip` action:
  - `arn:aws:sns:<region>:<account-id>:<topic>`
- Ensure the running identity has `sns:Publish` permissions to that topic.

## Automating with Lambda (optional)
You can deploy policies to Lambda for continuous enforcement by adding a `mode` block to specific policies, for example:

```yaml
mode:
  type: periodic
  schedule: "rate(1 hour)"
  role: arn:aws:iam::<account-id>:role/CloudCustodianLambdaRole
```

- Create an execution role with the permissions listed above and trust for `lambda.amazonaws.com`.
- Then run the same `custodian run ...` command; Custodian will package and deploy the Lambda functions.

For security-group changes, a reactive CloudTrail mode is useful:

```yaml
mode:
  type: cloudtrail
  role: arn:aws:iam::<account-id>:role/CloudCustodianLambdaRole
  events:
    - source: ec2.amazonaws.com
      event: AuthorizeSecurityGroupIngress
      ids: "requestParameters.groupId"
```

## Customization Tips
- Allowed SSH CIDRs: the provided policy removes `0.0.0.0/0` on port 22. If you need to allow specific office IPs, add a separate SG rule managed outside Custodian or replace the action with a `set-permissions` action defining the exact allowed list.
- Offhours window: adjust `offhour`, `onhour`, and `default_tz` to your schedule. You can also drive offhours with the `custodian_downtime` tag on instances for per-resource control.
- Tag keys: change `Owner` / `Environment` to your organization’s required tags, or switch the action to `mark-for-op` if you prefer to notify instead of auto-tagging.

## Safe Rollout
1. Start with `--dryrun` and verify matched resources.
2. Run only the least risky policies first (e.g., tagging, notifications).
3. Enable stop/encrypt actions in lower environments before production.
4. Add Lambda `mode` once you’re confident in behavior.

## Helpful Links
- Cloud Custodian docs: https://cloudcustodian.io/
- EC2 resource reference: https://cloudcustodian.io/docs/aws/resources/ec2.html
- Security Group reference: https://cloudcustodian.io/docs/aws/resources/securitygroup.html

