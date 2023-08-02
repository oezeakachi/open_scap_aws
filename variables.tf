// Variables that are used golbally in the terraform code

variable "namespace" {
  description = "The project namespace to use for unique resource naming"
  default     = "IMB"
  type        = string
}

variable "region" {
  description = "AWS region"
  default     = "eu-west-1"
  type        = string
} 


variable "SCAPScanResults" {
  description = "Name of the S3 bucket to store SCAP scan results"
  type        = string
  default     = "my-scap-scan-bucket"
}




variable "EnableSecurityHubFindings" {
  description = "Choose true if you would like the findings to be pushed to Security Hub, Security Hub must be turned on if true is selected."
  default     = "true"
}

