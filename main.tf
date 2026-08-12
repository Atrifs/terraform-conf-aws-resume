terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# --- 1. S3 BUCKET ---
resource "aws_s3_bucket" "existing" {
  bucket = "atrifs-cloud-resume-site"
}

# --- 2. CLOUDFRONT DISTRIBUTION ---
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.htm" # Updated to match live AWS setting

  tags = {
    Name = "atrifs-cloudfront"
  }

  origin {
    domain_name              = "atrifs-cloud-resume-site.s3.us-east-2.amazonaws.com"
    origin_id                = "atrifs-cloud-resume-site.s3.us-east-2.amazonaws.com-mselqd5mx76"
    origin_access_control_id = "EK2ML9LD6BDAS"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "atrifs-cloud-resume-site.s3.us-east-2.amazonaws.com-mselqd5mx76"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS Managed CachingOptimized Policy
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --- 3. DYNAMODB TABLE ---
resource "aws_dynamodb_table" "view_count" {
  name         = "IndexVisitCount" # Replace with live table name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"  # Replace with live partition key

  attribute {
    name = "id"
    type = "S"
  }
}

# --- 4. LAMBDA FUNCTION ---
resource "aws_lambda_function" "counter" {
  function_name = "updateViewCounter"
  role          = "arn:aws:iam::960233595137:role/service-role/updateViewCounter-role-nnzcmqs4"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.14"

  filename      = "lambda_placeholder.zip"

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      architectures,
      ephemeral_storage,
      logging_config,
      tracing_config
    ]
  }
}

# --- 5. API GATEWAY ---
resource "aws_apigatewayv2_api" "api" {
  name          = "resume-counter-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["GET", "OPTIONS"]
    allow_origins     = ["https://d2jr45qhlpmzfb.cloudfront.net"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_count" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}