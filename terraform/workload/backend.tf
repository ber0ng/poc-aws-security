terraform {
  backend "s3" {
    bucket       = "veron-poc-tfstate"
    key          = "workload/terraform.tfstate"
    region       = "ap-southeast-2"
    profile      = "poc-management"
    use_lockfile = true
  }
}
