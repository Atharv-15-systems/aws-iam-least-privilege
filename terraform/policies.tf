############################################
# Admins — near-full account control, but
# every action is DENIED unless the caller
# has authenticated with MFA. This is the
# standard AWS pattern for "enforce MFA for
# a group" since IAM groups themselves can't
# carry an MFA requirement directly.
############################################

data "aws_iam_policy_document" "admin_permissions" {
  statement {
    sid       = "AdminFullAccessWhenMFA"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "deny_all_without_mfa" {
  # Allow the bare minimum every user needs before they've even set up MFA:
  # viewing their own account/user info and managing their own MFA device.
  statement {
    sid    = "AllowViewAccountInfoWithoutMFA"
    effect = "Allow"
    actions = [
      "iam:GetAccountSummary",
      "iam:ListVirtualMFADevices",
      "iam:GetUser",
      "iam:ListUsers",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageOwnMFAWithoutMFA"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:ListMFADevices",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/&{aws:username}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/&{aws:username}",
    ]
  }

  statement {
    sid       = "AllowChangeOwnPasswordWithoutMFA"
    effect    = "Allow"
    actions   = ["iam:ChangePassword", "iam:GetLoginProfile"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/&{aws:username}"]
  }

  # Everything else requires MFA to have been presented for this session.
  statement {
    sid    = "DenyAllExceptListedIfNoMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "iam:ChangePassword",
      "iam:GetLoginProfile",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "admin_permissions" {
  name        = "${var.project_name}-AdminPermissions"
  description = "Admin-level access, only usable when MFA has been presented"
  policy      = data.aws_iam_policy_document.admin_permissions.json
}

resource "aws_iam_policy" "enforce_mfa" {
  name        = "${var.project_name}-EnforceMFA"
  description = "Denies almost all actions unless the principal has authenticated with MFA"
  policy      = data.aws_iam_policy_document.deny_all_without_mfa.json
}

resource "aws_iam_group_policy_attachment" "admins_permissions" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.admin_permissions.arn
}

resource "aws_iam_group_policy_attachment" "admins_enforce_mfa" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.enforce_mfa.arn
}

############################################
# Developers — can work with EC2, Lambda,
# and the app's own S3 bucket/logs. No IAM,
# no billing, no account-level actions.
############################################

data "aws_iam_policy_document" "developer_permissions" {
  statement {
    sid    = "EC2Development"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeImages",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
      "ec2:TerminateInstances",
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "AppBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "OwnLogsAccess"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/*"]
  }

  statement {
    sid       = "DenyIAMAndBilling"
    effect    = "Deny"
    actions   = ["iam:*", "aws-portal:*", "organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "developer_permissions" {
  name        = "${var.project_name}-DeveloperPermissions"
  description = "Least-privilege access for developers: EC2 lifecycle + scoped S3/log access, explicit deny on IAM/billing"
  policy      = data.aws_iam_policy_document.developer_permissions.json
}

resource "aws_iam_group_policy_attachment" "developers_permissions" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developer_permissions.arn
}

############################################
# Auditors — read-only across the account.
# No Allow statement in this policy contains
# a mutating verb (Create/Put/Delete/Update/
# Modify/Attach/Detach/Terminate/Run/Stop).
############################################

data "aws_iam_policy_document" "auditor_permissions" {
  statement {
    sid    = "ReadOnlyVisibility"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
      "iam:GenerateCredentialReport",
      "iam:GenerateServiceLastAccessedDetails",
      "ec2:Describe*",
      "s3:GetBucket*",
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:GetObject",
      "cloudtrail:LookupEvents",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:DescribeTrails",
      "config:Describe*",
      "config:Get*",
      "config:List*",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "logs:Describe*",
      "logs:Get*",
      "logs:FilterLogEvents",
      "trustedadvisor:Describe*",
      "ce:Get*",
      "ce:Describe*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyAnyMutatingAction"
    effect    = "Deny"
    actions   = ["iam:Create*", "iam:Delete*", "iam:Update*", "iam:Put*", "iam:Attach*", "iam:Detach*", "ec2:*Instance*", "s3:Delete*", "s3:Put*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "auditor_permissions" {
  name        = "${var.project_name}-AuditorPermissions"
  description = "Read-only visibility into IAM, EC2, S3, CloudTrail, Config, CloudWatch, and Cost Explorer"
  policy      = data.aws_iam_policy_document.auditor_permissions.json
}

resource "aws_iam_group_policy_attachment" "auditors_permissions" {
  group      = aws_iam_group.auditors.name
  policy_arn = aws_iam_policy.auditor_permissions.arn
}
