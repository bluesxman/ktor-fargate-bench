# ktor-fargate-bench

export AWS_PROFILE=ktor-admin
cd terraform/infra
tfenv use 0.11.14
terraform init --reconfigure --backend-config="bucket=com.smackwerks-tfstate"
