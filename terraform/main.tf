########################################
# VPC
########################################

resource "yandex_vpc_network" "main" {
  name = "diploma-network"
}

########################################
# Subnets
########################################

resource "yandex_vpc_subnet" "public_a" {
  name           = "public-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.0.0/24"]

}

resource "yandex_vpc_subnet" "private_a" {
  name           = "private-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.1.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

resource "yandex_vpc_subnet" "private_b" {
  name           = "private-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.2.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

########################################
# NAT Gateway
########################################

resource "yandex_vpc_gateway" "nat_gateway" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private_rt" {
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}
########################################
# Security Group — Bastion
########################################

resource "yandex_vpc_security_group" "sg_bastion" {
  name       = "sg-bastion"
  network_id = yandex_vpc_network.main.id

  # SSH только с твоего IP
  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["167.17.191.16/32"]
    #v4_cidr_blocks = ["178.64.137.192/32"]
    #v4_cidr_blocks = [var.your_ip_cidr]
  }
  # Allow Zabbix agent traffic from Zabbix server
  ingress {
    protocol       = "TCP"
    port           = 10050
    v4_cidr_blocks = ["10.10.0.32/32"]
  }
  # Разрешаем ICMP (по желанию)
  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Обязательно — HEALTHCHECKS для ALB
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["198.18.0.0/16"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

########################################
# Security Group — Web Servers
########################################

resource "yandex_vpc_security_group" "sg_web" {
  name       = "sg-web"
  network_id = yandex_vpc_network.main.id

  # SSH только с bastion
  ingress {
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.sg_bastion.id
  }

  # HTTP от ALB (подсеть public)
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["10.10.0.0/24"]
  }

  # HEALTHCHECKS ALB
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["198.18.0.0/16"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol       = "TCP"
    port           = 10050
    v4_cidr_blocks = ["10.10.0.32/32"]
  }
}
########################################
# Security Group — ALB
########################################

resource "yandex_vpc_security_group" "sg_alb" {
  name        = "sg-alb"
  network_id  = yandex_vpc_network.main.id
  description = "Security group for ALB"

  # Разрешаем весь исходящий трафик
  egress {
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Разрешаем HTTP клиентский трафик
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Разрешаем healthcheck от ALB
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["198.18.0.0/16"]
  }
}




########################################
# Bastion Host
########################################

resource "yandex_compute_instance" "bastion" {
  name                      = "bastion"
  hostname                  = "bastion"
  zone                      = "ru-central1-a"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true


  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80qm01ah03dkqb14lc" # Ubuntu 22.04
      size     = 30
      type     = "network-hdd"
    }
  }


  network_interface {
    subnet_id          = yandex_vpc_subnet.public_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_bastion.id]
  }


  metadata = {
    ssh-keys = "ubuntu:${var.public_ssh_key}"
  }
}
########################################
# Web server 1 (private, zone A)
########################################

resource "yandex_compute_instance" "web1" {
  name                      = "web-1"
  hostname                  = "web-1"
  zone                      = "ru-central1-a"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true


  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd817i7o8012578061ra"
      size     = 30
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_web.id]
  }


  metadata = {
    ssh-keys = "ubuntu:${var.public_ssh_key}"
  }
}

########################################
# Web server 2 (private, zone B)
########################################

resource "yandex_compute_instance" "web2" {
  name                      = "web-2"
  hostname                  = "web-2"
  zone                      = "ru-central1-b"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true


  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd817i7o8012578061ra"
      size     = 30
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_b.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_web.id]

  }


  metadata = {
    ssh-keys = "ubuntu:${var.public_ssh_key}"
  }
}

resource "yandex_vpc_subnet" "public_alb" {
  name           = "public-alb"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.10.0/24"]
}

resource "yandex_lb_target_group" "tg_web" {
  name = "tg-web"

  target {
    subnet_id = yandex_vpc_subnet.private_a.id
    address   = yandex_compute_instance.web1.network_interface[0].ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.private_b.id
    address   = yandex_compute_instance.web2.network_interface[0].ip_address
  }
}

resource "yandex_lb_network_load_balancer" "nlb" {
  name = "web-nlb"
  type = "external"

  listener {
    name        = "http"
    port        = 80
    target_port = 80
    protocol    = "tcp"
    external_address_spec {}
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.tg_web.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  zone        = "ru-central1-a"
  platform_id = "standard-v1"
  hostname    = "zabbix"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd80bm0rh4rkepi5ksdi" # ubuntu-22-04
      size     = 30
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.public_a.id
    nat       = true
    security_group_ids = [
      yandex_vpc_security_group.sg_bastion.id,
      yandex_vpc_security_group.sg_zabbix.id
    ]
  }

  metadata = {
    ssh-keys = "ubuntu:${var.public_ssh_key}"
  }

  allow_stopping_for_update = true
}
resource "yandex_vpc_security_group" "sg_zabbix" {
  name       = "sg-zabbix"
  network_id = yandex_vpc_network.main.id

  # Разрешаем доступ к веб-интерфейсу Zabbix
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH для администрирования (при необходимости)
  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"] # или твой IP
  }

  # Хост может делать исходящие запросы
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "yandex_vpc_security_group" "sg_elastic" {
  name       = "sg-elasticsearch"
  network_id = yandex_vpc_network.main.id

  # SSH только через bastion
  ingress {
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.sg_bastion.id
  }

  # Разрешаем доступ от Kibana к ES
  ingress {
    protocol       = "TCP"
    port           = 9200
    v4_cidr_blocks = ["10.10.0.0/24"] # cidr публичной подсети
  }

  # Исходящий весь
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "yandex_vpc_security_group" "sg_kibana" {
  name       = "sg-kibana"
  network_id = yandex_vpc_network.main.id

  # SSH для твоего IP
  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = [var.your_ip_cidr]
  }

  # Доступ к Kibana (5601)
  ingress {
    protocol       = "TCP"
    port           = 5601
    v4_cidr_blocks = [var.your_ip_cidr]
  }

  # Разрешить доступ к Elasticsearch (9200)
  egress {
    protocol       = "TCP"
    port           = 9200
    v4_cidr_blocks = ["10.10.1.0/24", "10.10.2.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "yandex_compute_instance" "elasticsearch" {
  name        = "elasticsearch"
  hostname    = "elasticsearch"
  platform_id = "standard-v1"
  zone        = "ru-central1-b"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd80bm0rh4rkepi5ksdi"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_b.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_elastic.id]
  }

  allow_stopping_for_update = true
}
resource "yandex_compute_instance" "kibana" {
  name        = "kibana"
  hostname    = "kibana"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80bm0rh4rkepi5ksdi"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_kibana.id]
  }

  allow_stopping_for_update = true
}
