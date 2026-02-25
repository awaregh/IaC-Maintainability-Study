variable "name_prefix" {
  description = "Prefix for resource names and bucket name"
  type        = string
}

variable "bucket_suffix" {
  description = "Unique suffix for the S3 bucket name"
  type        = string
}
