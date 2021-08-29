provider "template" {
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

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.arn
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.example.execution_arn}/*/*"
}

output "invoke-url" {
  value = aws_api_gateway_deployment.example.invoke_url
}
