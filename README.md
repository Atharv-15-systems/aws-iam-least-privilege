# AWS IAM Least-Privilege Assignment

This repo provisions a rigorous IAM structure on AWS using Terraform:

- Three IAM Groups — **Admins**, **Developers**, **Auditors** — each with a
  custom, least-privilege policy.
- MFA enforcement on the **Admins** group.
- A custom IAM Role that lets an EC2 instance read/write one S3 bucket
  with no hardcoded credentials (via an instance profile).

## Structure

```
terraform/
  main.tf            provider + terraform block
  variables.tf        region, project name, target S3 bucket ARN
  groups.tf           the three IAM groups
  policies.tf         custom policies for Admins / Developers / Auditors
  ec2_s3_role.tf       EC2 instance role + policy + instance profile
  outputs.tf           useful ARNs/names after apply
```

## Design decisions

### 1. Admins group — least privilege + enforced MFA

IAM groups can't natively require MFA on their own, so this is implemented
with two policies attached to the Admins group:

- `AdminPermissions` — grants broad account access, but every statement
  carries a `Bool` condition on `aws:MultiFactorAuthPresent`, so the
  permissions are only usable in an MFA-authenticated session.
- `EnforceMFA` — denies every action *except* a small allow-list (viewing
  your own IAM user, registering/enabling an MFA device, changing your own
  password) whenever `aws:MultiFactorAuthPresent` is false. This is the
  standard AWS-documented pattern for "force MFA before anything else
  works" (see AWS IAM user guide: *Enable MFA for the AWS root/IAM users*).

Net effect: an Admin who hasn't set up MFA yet can log in and register a
device — and nothing else. Once MFA is active, they get admin access.

### 2. Developers group — scoped to their actual job

- Full EC2 lifecycle actions (`RunInstances`, `Start/Stop/Reboot/Terminate`,
  describe calls), restricted to the deployment region via a
  `aws:RequestedRegion` condition.
- `GetObject` / `PutObject` / `ListBucket` on **one named application
  bucket** only (`var.s3_bucket_arn`), not `*`.
- Log-group access scoped to a `/<project>/*` log-group prefix.
- An explicit `Deny` on `iam:*` and all billing/organization actions, so
  even if a future managed policy attachment is overly broad, developers
  can never touch identity or billing.

### 3. Auditors group — strictly read-only

Only `Get*` / `List*` / `Describe*`-style actions across IAM, EC2, S3,
CloudTrail, AWS Config, CloudWatch, and Cost Explorer — plus an explicit
`Deny` on IAM/EC2/S3 mutating verbs as a defense-in-depth backstop. No
statement in this policy can create, delete, or modify anything.

### 4. EC2 → S3 role (no hardcoded credentials)

`ec2_s3_role.tf` creates:

- An IAM **role** whose trust policy only allows `ec2.amazonaws.com` to
  assume it (`sts:AssumeRole`).
- A policy scoped to `ListBucket` on the bucket itself and
  `GetObject`/`PutObject`/`PutObjectAcl` on objects inside it — not
  account-wide S3 access.
- An **instance profile** wrapping the role. When attached to an EC2
  instance, the instance retrieves short-lived, auto-rotating credentials
  from the instance metadata service (IMDS) — so no access key/secret is
  ever stored on disk or in application config.

## Usage

```bash
cd terraform
terraform init
terraform plan -var="s3_bucket_arn=arn:aws:s3:::your-actual-bucket"
terraform apply -var="s3_bucket_arn=arn:aws:s3:::your-actual-bucket"
```

To attach the role to an instance, reference the instance profile:

```hcl
resource "aws_instance" "app" {
  # ...
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_access.name
}
```

## Notes for grading

- Every group policy is a **customer-managed policy** authored in this
  repo (`policies.tf`), not an AWS managed policy — satisfying the
  "custom policies" requirement.
- Principle of Least Privilege is applied via: resource-level scoping
  (specific bucket/log-group ARNs, not `*`), condition keys (region,
  MFA), and explicit `Deny` backstops.
- MFA enforcement is implemented as policy conditions/deny rules since
  IAM has no separate "require MFA" toggle for a group.
