provider "template" {
  version = "~> 2.1"
}

resource "aws_api_gateway_rest_api" "example" {
  name        = "ServerlessExample"
  description = "Terraform Serverless Application Example"
  body        = data.template_file.example_swagger.rendered
}

data "template_file" example_swagger {
  template = file("../../swagger.yaml")

  vars = {
    lambda_invoke_arn = aws_lambda_function.example.invoke_arn
  }
}

resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  stage_name  = "default"
}

output "invoke-url" {
  value = aws_api_gateway_deployment.example.invoke_url
}
