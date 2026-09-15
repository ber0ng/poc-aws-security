#!/bin/bash

set -e

AWS_REGION="ap-southeast-2"
AWS_PROFILE="poc-workload"
AWS_ACCOUNT_ID="129264592348"
ECR_REPO="poc-aws-workload-frontend"
IMAGE_TAG="latest"

ECR_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "🔐 Logging into ECR..."
aws ecr get-login-password \
  --region $AWS_REGION \
  --profile $AWS_PROFILE | docker login \
  --username AWS \
  --password-stdin $ECR_URL

echo "🏗️ Building Docker image..."
docker build -t $ECR_REPO .

echo "🏷️ Tagging image..."
docker tag $ECR_REPO:$IMAGE_TAG $ECR_URL/$ECR_REPO:$IMAGE_TAG

echo "🚀 Pushing to ECR..."
docker push $ECR_URL/$ECR_REPO:$IMAGE_TAG

echo "✅ Done! Image pushed to $ECR_URL/$ECR_REPO:$IMAGE_TAG"