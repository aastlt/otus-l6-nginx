variable "yc_token" {
  type        = string
  description = "Yandex Cloud OAuth token"
}

variable "yc_cloud_id" {
  type        = string
  description = "Yandex Cloud ID"
}

variable "yc_folder_id" {
  type        = string
  description = "Yandex Cloud Folder ID"
}

variable "yc_zone" {
  type        = string
  default     = "ru-central1-a"
  description = "Yandex Cloud Zone"
}
