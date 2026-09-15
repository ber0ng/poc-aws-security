terraform {
  backend "s3" {
    bucket       = "veron-poc-tfstate"
    key          = "org/terraform.tfstate"
    region       = "ap-southeast-2"
    profile      = "poc-management"
    use_lockfile = true
  }
}
