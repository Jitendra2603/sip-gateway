variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "xi-playground"
}

variable "region" {
  description = "GCP region for the SIP gateway VM"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the SIP gateway VM"
  type        = string
  default     = "europe-west1-b"
}

variable "instance_name" {
  description = "Name for the GCE instance"
  type        = string
  default     = "sip-gateway"
}

variable "machine_type" {
  description = "GCE machine type (c2d-highcpu-2 is good for real-time media)"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "allowed_sip_source_ranges" {
  description = "CIDR ranges allowed to send SIP traffic. Use known LiveKit/ElevenLabs ranges, or 0.0.0.0/0 with digest auth enabled."
  type        = list(string)
  default     = ["199.88.252.0/24", "136.112.48.0/24", "143.223.88.0/21", "161.115.160.0/19"]
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed for SSH access. Use 35.235.240.0/20 for IAP-only."
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    team        = "convai"
    component   = "sip-gateway"
    environment = "playground"
  }
}
