output "sns_alarms_arn" {
  description = "SNS alarms topic ARN"
  value       = aws_sns_topic.alarms.arn
}
