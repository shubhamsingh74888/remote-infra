terraform {
  backend "s3" {
    bucket         = "my-s3-bucket-shubham-default" # Use the actual name created in s3.tf
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "wanderlust-shubham-default"   # Matches the name in dynamodb.tf
    encrypt        = true
  }
}
