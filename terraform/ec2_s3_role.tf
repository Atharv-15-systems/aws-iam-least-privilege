############################################
# EC2 -> S3 access role
#
# Lets an EC2 instance read/write a specific
# S3 bucket via its instance profile, with no
# access keys stored on the instance. The
# trust policy only allows the EC2 service to
# assume this role.
############################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_s3_access" {
  name               = "${var.project_name}-EC2-S3-Role"
  description        = "Allows EC2 instances to access one S3 bucket without hardcoded credentials"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_s3_access" {
  statement {
    sid    = "ListSpecificBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [var.s3_bucket_arn]
  }

  statement {
    sid    = "ReadWriteObjectsInBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${var.s3_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "ec2_s3_access" {
  name        = "${var.project_name}-EC2-S3-AccessPolicy"
  description = "Scoped read/write access to a single S3 bucket, for use by the EC2 instance role"
  policy      = data.aws_iam_policy_document.ec2_s3_access.json
}

resource "aws_iam_role_policy_attachment" "ec2_s3_access" {
  role       = aws_iam_role.ec2_s3_access.name
  policy_arn = aws_iam_policy.ec2_s3_access.arn
}

# Instance profile is what actually gets attached to the EC2 instance;
# the instance's SDK/CLI picks up temporary, auto-rotated credentials
# from it via the instance metadata service — never a static access key.
resource "aws_iam_instance_profile" "ec2_s3_access" {
  name = "${var.project_name}-EC2-S3-InstanceProfile"
  role = aws_iam_role.ec2_s3_access.name
}
