output "public_connection_string" {
  description = "Copy/Paste/Enter - You are in the matrix"
  value       = "ssh -i ${module.ssh-key.key_name}.pem fedora@${module.ec2.public_ip[0]}"
}