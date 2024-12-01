# Configure AWS provider
provider "aws" {
  region = "us-east-1" # ניתן לשנות לפי המיקום המועדף
}

# יצירת bucket ב-S3 לאחסון סרטים וסדרות
resource "aws_s3_bucket" "video_content" {
  bucket = "video-content-bucket-example"
  acl    = "private"
}

# יצירת Cognito User Pool לניהול משתמשים
resource "aws_cognito_user_pool" "user_pool" {
  name = "video-app-user-pool"
}

# יצירת Cognito App Client לניהול גישה לאפליקציה
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "video-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
}

# יצירת API Gateway
resource "aws_api_gateway_rest_api" "video_api" {
  name        = "video-api"
  description = "API for video content recommendations and streaming"
}

# יצירת Lambda function לביצוע חישובים או המלצות תוכן
resource "aws_lambda_function" "video_recommendation_lambda" {
  function_name = "videoRecommendationFunction"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs14.x"
  filename      = "function.zip"

  source_code_hash = filebase64sha256("function.zip")
}

# IAM Role עבור Lambda כדי לגשת לשירותים שונים
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# יצירת SageMaker Notebook Instance לאימון מודלים של למידת מכונה
resource "aws_sagemaker_notebook_instance" "ml_notebook" {
  name = "ml-model-notebook-instance"
  instance_type = "ml.t2.medium"
}

# יצירת סוויץ' CloudFront להפצת וידאו
resource "aws_cloudfront_distribution" "video_distribution" {
  origin {
    domain_name = aws_s3_bucket.video_content.bucket_regional_domain_name
    origin_id   = "S3-VideoContent"
  }

  enabled = true
  is_ipv6_enabled = true
  default_cache_behavior {
    target_origin_id = "S3-VideoContent"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods {
      items = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
    forward_cookies = "none"
    forward_query_string = false
  }
}

# יצירת S3 Bucket Policy להפצת התוכן
resource "aws_s3_bucket_object" "video_content_object" {
  bucket = aws_s3_bucket.video_content.id
  key    = "video/sample_video.mp4"
  source = "sample_video.mp4"  # מציין את קובץ הווידאו שברצונך להעלות
  acl    = "public-read"
}

# יצירת API Gateway Method להפניית בקשות ל-Lambda
resource "aws_api_gateway_resource" "lambda_resource" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  parent_id   = aws_api_gateway_rest_api.video_api.root_resource_id
  path_part   = "recommendations"
}

resource "aws_api_gateway_method" "lambda_method" {
  rest_api_id   = aws_api_gateway_rest_api.video_api.id
  resource_id   = aws_api_gateway_resource.lambda_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.lambda_method.http_method
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.video_recommendation_lambda.arn}/invocations"
}

# הפעלת Lambda על ידי API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_recommendation_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

# יצירת security group עבור Lambda (במקרה ויש צורך בחיבור לרשת VPC)
resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "Security Group for Lambda"
}

# יצירת התראת CloudWatch לניהול ניטור עבור Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.video_recommendation_lambda.function_name}"
}

# יצירת ה-Output
output "cloudfront_url" {
  value = aws_cloudfront_distribution.video_distribution.domain_name
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}
