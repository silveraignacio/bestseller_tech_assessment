provider "aws" {
	region = "us-east-2"
    access_key = "XXXXXXXXXXXXXXXXXXXXXXX"
    secret_key = "XXXXXXXXXXXXXXXXXXXXXXXXXX"
}


# Create the Role

resource "aws_iam_role" "S3BucketRole" {
  name = "S3_Access_Role"

  assume_role_policy = <<EOF
{
  "Version": "2020-12-23",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
     "Resource": [
        "arn:aws:s3:::<s3-bucket-name>"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
         "arn:aws:s3:::<s3-bucket-name>/*"
      ]
    }
  ]
}
EOF
}

#Find the AMI

data "aws_ami" "centos" {
  most_recent = true

  filter {
    name   = "name"
    values = ["MY_PersonalizedAMI"]
  }


  owners = ["11111111111111111111"] # My owner ID
}

# Create EC2 instance

resource "aws_instance" "EC2Instance" {
	ami = data.aws_ami.centos.id # Get AMI ID selected above
	instance_type 	= "t2.nano"

    tags = {
        Description = "New terraform EC2 instance"
        Name = "Terraform EC2 Instance"
        OS = "Centos 7"
    }

    subnet_id = "subnet-0b7541668ceccd0ec"
    associate_public_ip_address = false # Do not associate public IP

    #Install Apache
    user_data = <<EOF
		#! /bin/bash
        sudo su
        yum -y install httpd
		echo "Apache autoinstalled with terraform" >> /var/www/html/index.html
        systemctl start httpd
	EOF

}

#Create load balancer

resource "aws_lb" "Balancer" {
  name               = "LBBestseller"
  internal           = false
  load_balancer_type = "application"

  tags = {
    Environment = "test"
  }
}

# Create target group

resource "aws_lb_target_group" "tg-myapp" {
  name     = "my-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-xxxxxx"
}


# Attach target group to ALB

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.tg-myapp.arn
  target_id        = aws_instance.EC2Instance.id
  port             = 80
}


############################

##Task2

#Create autoscaling launch config

resource "aws_launch_configuration" "apache" {
  name_prefix = "apache-"

  image_id = data.aws_ami.centos.id # 
  instance_type = "t2.micro"
  associate_public_ip_address = true

   user_data = <<EOF
		#! /bin/bash
    sudo su
    yum -y install httpd
    echo "Apache autoinstalled with terraform" >> /var/www/html/index.html
    systemctl start httpd
   EOF

  lifecycle {
    create_before_destroy = true
  }
}

## Create Autoscaling group

resource "aws_autoscaling_group" "apache" {
  name = "Apache AutoScaling group"

  min_size             = 1
  max_size             = 3
  
  health_check_type    = "ELB"
  load_balancers = [
    aws_lb.Balancer.id
  ]

  launch_configuration = aws_launch_configuration.apache.name

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "instances-scale-up" {
    name = "instances-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = aws_autoscaling_group.apache.name
}

resource "aws_autoscaling_policy" "instances-scale-down" {
    name = "instances-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = aws_autoscaling_group.apache.name
}

resource "aws_cloudwatch_metric_alarm" "cpu-high" {
    alarm_name = "cpu-high-usage"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "120"
    statistic = "Average"
    threshold = "80"
    alarm_description = "CPU Usage on EC2 Instance is high!"
    alarm_actions = [
        aws_autoscaling_policy.instances-scale-up.arn
       ]
    dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.apache.name
    }
}

resource "aws_cloudwatch_metric_alarm" "cpu-low" {
    alarm_name = "cpu-low-usage"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "120"
    statistic = "Average"
    threshold = "60"
    alarm_description = "CPU Usage on EC2 Instance is low!"
    alarm_actions = [
        "${aws_autoscaling_policy.instances-scale-down.arn}"
    ]
    dimensions = {
        AutoScalingGroupName = "${aws_autoscaling_group.apache.name}"
    }
}
