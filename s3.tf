/*resource "aws_s3_bucket" "my_s3_bucket" {
 bucket = "my-s3-bucket-shubham-${terraform.workspace}"
 tags = {
  Name = "wanderlust-s3-${terraform.workspace}"
  Environment = terraform.workspace
 }
}
*/


resource "aws_s3_bucket" "my_s3_bucket" {
  bucket = "my-s3-bucket-shubham-${terraform.workspace}"

  tags = {
    Name        = "wanderlust-s3-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

# Versioning — keeps 30 days of backup history
# If a backup gets corrupted, you can recover older version
resource "aws_s3_bucket_versioning" "my_s3_bucket" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption — all files stored encrypted at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "my_s3_bucket" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — backups must never be public
resource "aws_s3_bucket_public_access_block" "my_s3_bucket" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
