resource "aws_globalaccelerator_accelerator" "main" {
  name            = "${var.project_name}-Accelerator"
  ip_address_type = "IPV4"
  enabled         = true

  tags = {
    Name    = "${var.project_name}-Accelerator"
    Project = var.project_name
  }
}

resource "aws_globalaccelerator_listener" "http" {
  accelerator_arn = aws_globalaccelerator_accelerator.main.id
  client_affinity = "SOURCE_IP"
  protocol        = "TCP"

  port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_globalaccelerator_endpoint_group" "primary" {
  listener_arn = aws_globalaccelerator_listener.http.id
  endpoint_group_region = var.primary_region

  endpoint_configuration {
    endpoint_id                    = aws_instance.primary.id
    weight                         = 100
    client_ip_preservation_enabled = true
  }
}

resource "aws_globalaccelerator_endpoint_group" "secondary" {
  listener_arn = aws_globalaccelerator_listener.http.id
  endpoint_group_region = var.secondary_region

  endpoint_configuration {
    endpoint_id                    = aws_instance.secondary.id
    weight                         = 0 # Initially 0, automation will update this
    client_ip_preservation_enabled = true
  }
}

output "global_accelerator_dns_name" {
  value = aws_globalaccelerator_accelerator.main.dns_name
}
