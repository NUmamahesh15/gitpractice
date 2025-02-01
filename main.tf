resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr_block

  tags = {
    name = "myvpc"
  }
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "eu-west-1a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "eu-west-1b"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "myvpc_igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "myrt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myvpc_igw.id
  }

}

resource "aws_route_table_association" "rt_sub1" {
  route_table_id = aws_route_table.myrt.id
  subnet_id      = aws_subnet.sub1.id
}

resource "aws_route_table_association" "rt_sub2" {
  route_table_id = aws_route_table.myrt.id
  subnet_id      = aws_subnet.sub2.id
}


resource "aws_security_group" "mysg" {
  name   = "web-sg-"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "TLS for VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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
}

resource "aws_s3_bucket" "mys3" {
  bucket = "nit-terr-s3"
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.mys3.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

}
resource "aws_s3_bucket_ownership_controls" "example2" {
  bucket = aws_s3_bucket.mys3.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "s3_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.example2,
    aws_s3_bucket_public_access_block.example,
  ]
  bucket = aws_s3_bucket.mys3.id
  acl    = "public-read"
}

resource "aws_instance" "server1" {
  ami                    = "ami-03fd334507439f4d1"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.mysg.id]
  subnet_id              = aws_subnet.sub1.id
  user_data              = base64encode(file("userdata.sh"))
}

resource "aws_instance" "server2" {
  ami                    = "ami-03fd334507439f4d1"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.sub2.id
  vpc_security_group_ids = [aws_security_group.mysg.id]
  user_data              = base64encode(file("userdata1.sh"))
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "myalb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mysg.id]
  subnets            = [aws_subnet.sub1.id, aws_subnet.sub2.id]

}

resource "aws_lb_target_group" "target_group" {
  name     = "mytg"
  port     = 80
  vpc_id   = aws_vpc.myvpc.id
  protocol = "HTTP"

  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "tar-attach1" {
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.server1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "tar-attach2" {
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.server2.id
  port             = 80
}

resource "aws_lb_listener" "list" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}

output "loadbalancer" {
  value = aws_lb.alb.dns_name
}