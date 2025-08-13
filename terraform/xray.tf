resource "aws_xray_sampling_rule" "xray" {
  rule_name      = "Flask"
  resource_arn   = "*"
  priority       = 9000
  fixed_rate     = 0.1
  reservoir_size = 5
  service_name   = "backend-flask"
  service_type   = "*"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  version        = 1
}

