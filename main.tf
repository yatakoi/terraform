#############################################################################
# ВХОДНЫЕ ПЕРЕМЕННЫЕ
#############################################################################

variable "server_port" {
  description = "Этот порт используется для запросов по HTTP"
  default = "8080"
}

#############################################################################
# ВЫХОДНЫЕ ПЕРЕМЕННЫЕ
#############################################################################

# Показать белый IP инстанса 'web-server'
output "public_ip" {
  value = "${aws_instance.web-server.public_ip}"
}


#############################################################################
# КАКОЙ ИСПОЛЬЗУЕТСЯ ПРОВАЙДЕР И РЕГИОН
#############################################################################

provider "aws" {
  region = "us-east-1"
}



#############################################################################
# ИНСТАНСЫ
#############################################################################

# Отказоустойчивый кластер веб-сервера
resource "aws_launch_configuration" "first-server" {
  ami           = "ami-40d28157"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.instance.id}"]

user_data = <<-EOF
            #!/bin/bash
            echo "Hello, World" > index.html
            nohup busybox httpd -f -p "${var.server_port}" &
            EOF
            
lifecycle {
  create_before_destroy = true
}

tags            =  {
  Name          = "Failover WebServer"
 }
}

# Веб-сервер на Ubuntu 
resource "aws_instance" "web-server" {
  ami		= "ami-40d28157"
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.instance.id}"]

user_data	= <<-EOF
		  #!/bin/bash
		  echo "Hello, World" > index.html
		  nohup busybox httpd -f -p "${var.server_port}" &
		  EOF

tags            =  {
  Name          = "web-server"
 }
}

#############################################################################
# VPCs
#############################################################################

resource "aws_security_group" "instance" {
  name		= "terraform-instance"

  ingress {
    from_port	= var.server_port
    to_port	= var.server_port
    protocol	= "tcp"
    cidr_blocks	= ["0.0.0.0/0"]
  }
}
