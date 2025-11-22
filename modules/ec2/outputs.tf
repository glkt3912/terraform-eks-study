# =============================================================================
# EC2 Module - Outputs
# =============================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.this.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.this.public_dns
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.this.id
}

output "web_url" {
  description = "URL of the web server"
  value       = "http://${aws_instance.this.public_ip}"
}
