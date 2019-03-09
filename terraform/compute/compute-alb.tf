### Load Balancer

resource "aws_alb" "main" {
  name            = "${local.project}-load-balancer"
  subnets         = ["${local.public_subnets}"]  # beware of list bugs:  https://github.com/hashicorp/terraform/issues/13869
  security_groups = ["${aws_security_group.lb.id}"]
}

resource "aws_alb_target_group" "app" {
  name        = "${local.project}-target-group"
  port        = "${local.app_port}"
  protocol    = "HTTP"
  vpc_id      = "${local.vpc_id}"
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "${local.elb_port}"
  protocol          = "HTTP"

  # Redirect all traffic from the ALB to the target group
  default_action {
    target_group_arn = "${aws_alb_target_group.app.id}"
    type             = "forward"
  }
}
