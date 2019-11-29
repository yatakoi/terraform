#############################################################################
# ВХОДНЫЕ ПЕРЕМЕННЫЕ
#############################################################################

variable "server_port" {
  description = "Этот порт используется для HTTP запросов"
  default     = "8080"
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

# Получить ID VPC из aws_vpc
data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

# Поиск данных в Default VPC
data "aws_vpc" "default" {
default = true
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
    
    # Включаем интеграцию между ASG и ALB, указыв аргумент target_group_arns 
    # на целевую группу aws_lb_target_group.asg.arn,
    # чтобы целевая группа знала, в какие инстансы EC2 отправлять запросы    
    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"
        
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
# ALB - Application Load Balancer
#############################################################################

# Создаем ресурс прослушиватель по HTTP
resource "aws_lb_listener" "http" {
    load_balancer_arn   = aws_lb.example.arn
    port                = 80
    protocol            = "HTTP"

# По умолчанию возвращаем простую 404 страницу
    default_action {
        type = "fixed-response"

        fixed_response {
            content_type    = "text/plain"
            message_body    = "404: страница не найдена"
            status_code     = 404
        }
    }
}    

# Создаем ресурс aws_security_group для ALB
# Разрешаем ALB входящий трафик на порт 80 и исходящий на любой другой   
resource "aws_security_group" "alb" {
    name = "terraform-example-alb"
    
    # Разрешить входящие запросы HTTP
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Разрешить все исходящие запросы
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Создаем ресурс aws_lb и указываем ему использовать подсеть default
# и aws_security_group alb
resource "aws_lb" "example" {
    name                = "terraform-asg-example"
    load_balancer_type  = "application"
    subnets             = data.aws_subnet_ids.default.ids
    security_groups     = [aws_security_group.alb.id]
}

# Создаём ресурс aws_lb_target_group для ASG
# Каждые 15 сек. будут отправляться HTTP запросы и если ответ 200, то все ОК, иначе
# произойдет переключение на доступный инстанс 
resource "aws_lb_target_group" "asg" {
    name = "terraform-asg-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
        interval            = 15
        timeout             = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}


# Включаем правило прослушивателя, которое отправляет запросы,
# соответствующие любому пути, в целевую группу для ASG 
resource "aws_lb_listener_rule" "asg" {
    listener_arn    = aws_lb_listener.http.arn
    priority        = 100
    
    condition {
        field   = "path-pattern"
        values  = ["*"]
    }
    
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}

# Вывод DNS ALB
output "alb_dns_name" {
    value = aws_lb.example.dns_name
    description = "Доменное имя ALB"
}