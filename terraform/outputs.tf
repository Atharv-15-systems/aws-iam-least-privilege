output "admins_group_name" {
  value = aws_iam_group.admins.name
}

output "developers_group_name" {
  value = aws_iam_group.developers.name
}

output "auditors_group_name" {
  value = aws_iam_group.auditors.name
}

output "ec2_s3_role_arn" {
  description = "Attach this role's instance profile to an EC2 instance to give it S3 access with no hardcoded credentials"
  value       = aws_iam_role.ec2_s3_access.arn
}

output "ec2_s3_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_s3_access.name
}
