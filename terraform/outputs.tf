output "lb_public_ip" {
  value = yandex_compute_instance.balancer.network_interface.0.nat_ip_address
}

output "app_internal_ips" {
  value = yandex_compute_instance.app[*].network_interface.0.ip_address
}

output "db_internal_ip" {
  value = yandex_compute_instance.db.network_interface.0.ip_address
}
