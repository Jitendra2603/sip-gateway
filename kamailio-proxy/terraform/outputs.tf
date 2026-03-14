output "sip_gateway_static_ip" {
  description = "Static external IP of the SIP gateway"
  value       = google_compute_address.sip_gateway.address
}

output "sip_gateway_instance_name" {
  description = "Name of the GCE instance"
  value       = google_compute_instance.sip_gateway.name
}

output "sip_gateway_zone" {
  description = "Zone of the GCE instance"
  value       = google_compute_instance.sip_gateway.zone
}

output "sip_uri" {
  description = "SIP URI to configure as outbound trunk address"
  value       = "${google_compute_address.sip_gateway.address}:5060"
}

output "sip_uri_tcp" {
  description = "SIP TCP URI for outbound trunk"
  value       = "${google_compute_address.sip_gateway.address}:5060;transport=tcp"
}
