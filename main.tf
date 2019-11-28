#############################################################################
# ВХОДНЫЕ ПЕРЕМЕННЫЕ
#############################################################################

variable "server_port" {
  description = "Этот порт используется для HTTP запросов"
  default     = "8080"
}

#############################################################################
# КАКОЙ ИСПОЛЬЗУЕТСЯ ПРОВАЙДЕР И РЕГИОН
#############################################################################

provider "aws" {
  region = "us-east-2"
}

#############################################################################
# ИНСТАНСЫ
#############################################################################

# FILEOVER ВЕБ-СЕРВЕР НА UBUNTU 
resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    
    min_size = 2
    max_size = 10
    
    tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
    }
}

resource "aws_launch_configuration" "example" {
    image_id = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"

    security_groups = [aws_security_group.instance.id]
                user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    # Требуется при использовании launch configuration совместно с auto scaling group.
    # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
    lifecycle {
        create_before_destroy = true
    }
}


#############################################################################
# VPC Security Groups
#############################################################################

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port	    = var.server_port
    to_port	        = var.server_port
    protocol	    = "tcp"
    cidr_blocks	    = ["0.0.0.0/0"]
    }
}

data "aws_vpc" "default" {
default = true
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}