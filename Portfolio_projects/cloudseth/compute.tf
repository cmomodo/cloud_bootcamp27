# --- AMI Data Sources ---

data "aws_ami" "amazon_linux_primary" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_ami" "amazon_linux_secondary" {
  provider    = aws.secondary
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# --- Primary Region Compute ---

resource "aws_instance" "primary" {
  ami           = data.aws_ami.amazon_linux_primary.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.primary.id
  vpc_security_group_ids = [aws_security_group.primary_web.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Primary Region (${var.primary_region})</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name    = "${var.project_name}-Primary-Web"
    Project = var.project_name
  }
}

# --- Secondary Region Compute ---

resource "aws_instance" "secondary" {
  provider      = aws.secondary
  ami           = data.aws_ami.amazon_linux_secondary.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.secondary.id
  vpc_security_group_ids = [aws_security_group.secondary_web.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Secondary Region (${var.secondary_region})</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name    = "${var.project_name}-Secondary-Web"
    Project = var.project_name
  }
}

# Ensure Secondary Instance is Stopped (Pilot Light)
resource "aws_ec2_instance_state" "secondary_state" {
  provider    = aws.secondary
  instance_id = aws_instance.secondary.id
  state       = "stopped"
}
