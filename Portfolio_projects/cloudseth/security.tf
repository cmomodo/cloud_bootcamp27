# --- Primary Region Security Group ---

resource "aws_security_group" "primary_web" {
  name        = "${var.project_name}-Primary-Web-SG"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.primary.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-Primary-Web-SG"
    Project = var.project_name
  }
}

# --- Secondary Region Security Group ---

resource "aws_security_group" "secondary_web" {
  provider    = aws.secondary
  name        = "${var.project_name}-Secondary-Web-SG"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.secondary.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-Secondary-Web-SG"
    Project = var.project_name
  }
}
