# 1. Сеть
resource "yandex_vpc_network" "network" {
  name = "wp-network"
}

# 2. NAT-шлюз
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "gateway"
  shared_egress_gateway {}
}

# 3. Таблица маршрутизации
resource "yandex_vpc_route_table" "rt" {
  network_id = yandex_vpc_network.network.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

# 4. Подсеть
resource "yandex_vpc_subnet" "subnet" {
  name           = "wp-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}

# 5. Security Group (Разрешаем HTTP, SSH и внутренний трафик)
resource "yandex_vpc_security_group" "web-sg" {
  name       = "web-sg"
  network_id = yandex_vpc_network.network.id

  # Внешний входящий трафик
  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  # ВНУТРЕННИЙ трафик — разрешаем всё между нодами
  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["192.168.10.0/24"]
    from_port      = 0
    to_port        = 65535
  }

  # Исходящий трафик (обязательно для ответов серверов)
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# 6. Образ ОС
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

locals {
  vm_user = "ubuntu"
  ssh_key = file("~/.ssh/id_rsa.pub")
}

# 8. Балансировщик
resource "yandex_compute_instance" "balancer" {
  name     = "nginx-lb"
  hostname = "nginx-lb"
  
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web-sg.id] # ДОБАВЛЕНО
  }
  metadata = {
    ssh-keys = "${local.vm_user}:${local.ssh_key}"
  }
}

# 9. Фронтенды
resource "yandex_compute_instance" "app" {
  count    = 2
  name     = "wp-app-${count.index + 1}"
  hostname = "wp-app-${count.index + 1}"

  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    security_group_ids = [yandex_vpc_security_group.web-sg.id] # ДОБАВЛЕНО
  }
  metadata = {
    ssh-keys = "${local.vm_user}:${local.ssh_key}"
  }
}

# 10. База данных
resource "yandex_compute_instance" "db" {
  name     = "wp-db"
  hostname = "wp-db"

  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    security_group_ids = [yandex_vpc_security_group.web-sg.id] # ДОБАВЛЕНО
  }
  metadata = {
    ssh-keys = "${local.vm_user}:${local.ssh_key}"
  }
}

# 11. Ansible Inventory Generation
resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tftpl",
    {
      lb_ip   = yandex_compute_instance.balancer.network_interface.0.nat_ip_address
      app_ips = yandex_compute_instance.app[*].network_interface.0.ip_address
      db_ip   = yandex_compute_instance.db.network_interface.0.ip_address
    }
  )
  filename = "../ansible/inventory.ini"
}

# 12. Ansible Provisioning Run
resource "null_resource" "ansible_run" {
  depends_on = [
    yandex_compute_instance.balancer,
    yandex_compute_instance.app,
    yandex_compute_instance.db,
    local_file.ansible_inventory
  ]

  triggers = {
    lb_ip = yandex_compute_instance.balancer.network_interface.0.nat_ip_address
  }

  provisioner "local-exec" {
    command = <<EOT
      echo "Hard cleanup of SSH known_hosts..."
      rm -f ~/.ssh/known_hosts
      echo "Waiting 50s for Cloud-Init and Network to be ready..."
      sleep 50
      cd ../ansible
      export ANSIBLE_HOST_KEY_CHECKING=False
      ansible-playbook site.yml
    EOT
  }
}
