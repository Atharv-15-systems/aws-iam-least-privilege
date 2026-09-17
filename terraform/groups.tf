############################################
# IAM Groups
############################################

resource "aws_iam_group" "admins" {
  name = "${var.project_name}-Admins"
  path = "/"
}

resource "aws_iam_group" "developers" {
  name = "${var.project_name}-Developers"
  path = "/"
}

resource "aws_iam_group" "auditors" {
  name = "${var.project_name}-Auditors"
  path = "/"
}
