

variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "folder_id" {
  description = "Yandex Folder ID"
  type        = string
}

variable "zone" {
  description = "Availability zone"
  default     = "ru-central1-a"
}
variable "public_ssh_key" {
  description = "Public SSH key for accessing instances"
  type        = string
}
variable "yc_key_file" {
  description = "Path to the Yandex Cloud service account key file"
  type        = string
}

variable "your_ip_cidr" {
  type        = string
  description = "Ваш внешний IP в формате CIDR, например 95.24.33.11/32"
}
