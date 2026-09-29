# =====================================================================
# 1. Remote state: S3 bucket + DynamoDB lock table
#    (GitHub Actions and your laptop share ONE source of truth)
# =====================================================================

resource "aws_s3_bucket" "state" {
  bucket = "tfstate-${local.account_id}"
  lifecycle { prevent_destroy = true } # never lose state by accident
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" } # undo a bad state write
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 } # keep storage ~$0
  }
}

resource "aws_dynamodb_table" "lock" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# =====================================================================
# 2. GitHub OIDC: GitHub proves who it is, AWS gives a 1-hour login
# =====================================================================

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

resource "aws_iam_role" "github_deploy" {
  name                 = "github-actions-visitor-counter"
  max_session_duration = 3600

  # ONLY this repo (matched by immutable IDs), ONLY main branch pushes or pull requests
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:ref:refs/heads/main",
            "repo:${var.github_repo}:pull_request"
          ]
        }
      }
    }]
  })
}

# =====================================================================
# 3. Permissions: only what the visitor counter needs, only its resources
# =====================================================================

resource "aws_iam_role_policy" "github_deploy" {
  name = "visitor-counter-deploy"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/visitor-counter/*"]
      },
      {
        Sid      = "TerraformLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
        Resource = aws_dynamodb_table.lock.arn
      },
      {
        Sid      = "AppDynamo"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:us-east-1:${local.account_id}:table/visitor-counter"
      },
      {
        Sid      = "AppLambda"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:us-east-1:${local.account_id}:function:visitor-counter"
      },
      {
        Sid    = "AppLogs"
        Effect = "Allow"
        Action = "logs:*"
        Resource = [
          "arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/visitor-counter",
          "arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/visitor-counter:*"
        ]
      },
      {
        Sid      = "LogsDescribe"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid      = "AppIamRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:PutRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:PassRole"]
        Resource = "arn:aws:iam::${local.account_id}:role/visitor-counter-lambda-role"
      },
      {
        Sid      = "AppApiGateway"
        Effect   = "Allow"
        Action   = "apigateway:*"
        Resource = "arn:aws:apigateway:us-east-1::/apis*"
      }
    ]
  })
}

output "role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}
