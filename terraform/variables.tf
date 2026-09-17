variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used to name/tag all resources created by this assignment"
  type        = string
  default     = "iam-assignment"
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the EC2 role is allowed to access. Update this to your actual bucket."
  type        = string
  default     = "arn:aws:s3:::iam-assignment-app-bucket"
}
