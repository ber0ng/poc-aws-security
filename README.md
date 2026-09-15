# AWS Security POC — ISO 27001 Ready Infrastructure

A end-to-end AWS security proof of concept demonstrating ISO 27001-aligned cloud infrastructure using AWS Organizations, ECS Fargate, IAM Identity Center, and a full security tooling stack. Built entirely with Terraform and deployed via GitHub Actions OIDC.

---

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full Mermaid diagram.

---

## Account Structure

| Account            | ID             | OU           | Purpose                                     |
| ------------------ | -------------- | ------------ | ------------------------------------------- |
| Management (Veron) | `835107xxxxxx` | Root         | Org root, Terraform state, SCPs             |
| poc-security       | `962635xxxxxx` | Security OU  | GuardDuty, Security Hub, CloudTrail, Config |
| poc-workload       | `129264xxxxxx` | Workloads OU | VPC, ECS, ALB, app workloads                |

---

## IAM Identity Center (SSO)

Access is managed through AWS IAM Identity Center — no IAM users or static access keys anywhere.

**SSO Portal URL:**

```
https://ssoins-xxxxxxxxxxxxxxxx.portal.ap-southeast-2.app.aws
```

| Group             | Accounts                                 | Permission Set        |
| ----------------- | ---------------------------------------- | --------------------- |
| `Security Admin`  | management + poc-security + poc-workload | `AdministratorAccess` |
| `Workloads Admin` | poc-workload                             | `WorkloadAdminAccess` |
| `General Users`   | poc-workload                             | `GeneralReadOnly`     |

---

## Security Controls (ISO 27001 Mapping)

| Control                | ISO 27001 | Implementation                                                    |
| ---------------------- | --------- | ----------------------------------------------------------------- |
| Centralized identity   | A.8       | IAM Identity Center SSO, no IAM users or static keys              |
| Least privilege access | A.8       | Permission sets per group, read-only for general users            |
| Root access protection | A.8       | Centralized root access enabled via IAM                           |
| Separation of duties   | A.8       | Security Admin vs Workloads Admin vs General Users                |
| Org-level guardrails   | A.8       | SCPs: deny disable CloudTrail, GuardDuty, public S3, leave org    |
| Threat detection       | A.12      | GuardDuty enabled org-wide                                        |
| Security posture       | A.12      | Security Hub — CIS v1.4 + AWS FSBP standards                      |
| Audit logging          | A.12      | CloudTrail org-level trail → S3, log file validation enabled      |
| Config compliance      | A.12      | AWS Config — S3 public access, EBS encryption, root MFA rules     |
| Secrets management     | A.13      | Secrets Manager + KMS CMK, no plaintext secrets in env vars       |
| Network isolation      | A.13      | ECS tasks in private subnets only, VPC endpoints for AWS services |
| Encryption at rest     | A.14      | KMS CMK for ECR, Secrets Manager                                  |
| Encryption in transit  | A.14      | HTTPS on ALB, ACM certificate                                     |
| CI/CD security         | A.14      | GitHub Actions OIDC — no static AWS keys in GitHub                |
| Container security     | A.14      | ECR scan on push + Trivy scan gate before every image push        |
| Static analysis (SAST) | A.14      | CodeQL on `app/**` (backend + frontend)                           |
| IaC misconfig scanning | A.14      | tfsec on `terraform/**`                                           |
| Secret scanning        | A.14      | gitleaks on every push/PR                                         |

---

## Tech Stack

| Layer                   | Technology                             |
| ----------------------- | -------------------------------------- |
| Infrastructure as Code  | Terraform >= 1.10                      |
| Container Orchestration | AWS ECS Fargate                        |
| Load Balancer           | AWS ALB                                |
| Backend                 | Node.js / TypeScript                   |
| Frontend                | React / TypeScript (Vite)              |
| Database                | In-memory (POC)                        |
| Secrets                 | AWS Secrets Manager + KMS CMK          |
| CI/CD                   | GitHub Actions (OIDC — no static keys) |
| Container Registry      | Amazon ECR (scan on push)              |
| DNS                     | AWS ALB DNS (Cloudflare ready)         |
| Threat Detection        | AWS GuardDuty                          |
| Security Posture        | AWS Security Hub (CIS + FSBP)          |
| Audit Logging           | AWS CloudTrail (org-level)             |
| Config Compliance       | AWS Config                             |
| Identity                | AWS IAM Identity Center (SSO)          |
| Org Guardrails          | AWS Organizations SCPs                 |

---

## Repository Structure

```
aws-security-poc/
├── terraform/
│   ├── org/                      # SCPs, org-level policies (management account)
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── backend.tf
│   │   └── variables.tf
│   ├── security-account/         # GuardDuty, Security Hub, CloudTrail, Config
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── backend.tf
│   │   └── variables.tf
│   ├── workload/                 # VPC, ECS, ALB, KMS, Secrets, OIDC
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── backend.tf
│   │   └── variables.tf
│   └── modules/
│       ├── ecs-service/          # Reusable ECS Fargate service module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── alb/
│       └── security-baseline/
├── app/
│   ├── backend/                  # Node.js/TypeScript REST API
│   │   ├── src/
│   │   │   └── index.ts
│   │   ├── Dockerfile
│   │   ├── deploy.sh
│   │   ├── tsconfig.json
│   │   └── package.json
│   └── frontend/                 # React/TypeScript (Vite)
│       ├── src/
│       │   ├── App.tsx
│       │   └── App.css
│       ├── Dockerfile
│       ├── deploy.sh
│       └── package.json
├── .github/
│   └── workflows/
│       ├── backend-deploy.yaml   # OIDC → ECR push (Trivy scan gate) → ECS deploy
│       ├── frontend-deploy.yaml  # OIDC → ECR push (Trivy scan gate) → ECS deploy
│       ├── codeql.yaml           # CodeQL SAST on app/**
│       ├── iac-scan.yaml         # tfsec scan on terraform/**
│       └── secret-scan.yaml      # gitleaks scan on every push/PR
└── README.md
```

---

## Prerequisites

- AWS CLI v2
- Terraform >= 1.10
- Node.js >= 20
- Docker Desktop
- Git

---

## Step-by-Step Setup Guide

### Phase 1 — AWS Organizations (Console)

1. Log into your management AWS account
2. Go to **AWS Organizations** → **Create organization** → select **All features**
3. Create two OUs under Root:
   - `Security` OU
   - `Workloads` OU
4. Create two member accounts:
   - `poc-security` → place in Security OU (use Gmail `+` alias e.g. `yourmail+poc-security@gmail.com`)
   - `poc-workload` → place in Workloads OU (e.g. `yourmail+poc-workload@gmail.com`)
5. Go to **IAM → Account Settings** → **Centralize root access for member accounts** → **Enable in IAM**
   - Set delegated administrator to `poc-security` account ID
   - Enable both: Root credentials management + Privileged root actions

### Phase 2 — IAM Identity Center (Console)

1. Go to **IAM Identity Center** → **Settings**
2. Create groups:
   - `Security Admin` — full admin access
   - `Workloads Admin` — workload account access
   - `General Users` — read-only access
3. Create users and add to appropriate groups
4. Create permission sets:
   - `SecurityAdminAccess` → `AdministratorAccess` policy, 4hr session
   - `SecurityAuditAccess` → `SecurityAudit` policy, 2hr session
   - `WorkloadAdminAccess` → `AdministratorAccess` policy, 4hr session
   - `GeneralReadOnly` → `ReadOnlyAccess` policy, 2hr session
5. Assign accounts:
   - `poc-security` → Security Admin group + `SecurityAdminAccess`
   - `poc-workload` → Security Admin group + `WorkloadAdminAccess`
   - `poc-workload` → Workloads Admin group + `WorkloadAdminAccess`
   - `poc-workload` → General Users group + `GeneralReadOnly`
   - `management` → Security Admin group + `AdministratorAccess`
6. Go to **Organizations → Policies → Service Control Policies** → **Enable**

### Phase 3 — Terraform State Backend (Console)

In the **management account**, create:

1. **S3 bucket** for Terraform state:
   - Name: `veron-poc-tfstate`
   - Region: `ap-southeast-2`
   - Block all public access ✅
   - Enable versioning ✅
   - Enable SSE-S3 encryption ✅

> **Note:** No DynamoDB table needed — Terraform >= 1.10 supports native S3 state locking via `use_lockfile = true`

### Phase 4 — Local AWS CLI Setup

1. Install AWS CLI v2 and Terraform >= 1.10

2. Configure SSO:

```bash
aws configure sso --profile poc-management
```

```
SSO session name: poc-sso
SSO start URL: https://ssoins-xxxxxxxxxxxxxxxx.portal.ap-southeast-2.app.aws
SSO region: ap-southeast-2
SSO registration scopes: sso:account:access
```

3. Repeat for other profiles:

```bash
aws configure sso --profile poc-security
aws configure sso --profile poc-workload
```

4. Your `~/.aws/config` should look like:

```ini
[profile poc-management]
sso_session = poc-sso
sso_account_id = <management-account-id>
sso_role_name = AdministratorAccess
region = ap-southeast-2

[profile poc-security]
sso_session = poc-sso
sso_account_id = <security-account-id>
sso_role_name = AdministratorAccess
region = ap-southeast-2

[profile poc-workload]
sso_session = poc-sso
sso_account_id = <workload-account-id>
sso_role_name = AdministratorAccess
region = ap-southeast-2

[sso-session poc-sso]
sso_start_url = https://ssoins-xxxxxxxxxxxxxxxx.portal.ap-southeast-2.app.aws
sso_region = ap-southeast-2
sso_registration_scopes = sso:account:access
```

5. Login:

```bash
aws sso login --profile poc-management
```

6. Verify all three profiles:

```bash
aws sts get-caller-identity --profile poc-management
aws sts get-caller-identity --profile poc-security
aws sts get-caller-identity --profile poc-workload
```

### Phase 5 — Terraform Deploy

Deploy in this order:

**1. Workload infrastructure:**

```bash
cd terraform/workload
terraform init
terraform plan
terraform apply
```

This creates: VPC, subnets, NAT gateway, ECR repos, ECS cluster, ALB, KMS, Secrets Manager, OIDC provider, GitHub Actions role

**2. Security account:**

```bash
cd terraform/security-account
terraform init
terraform plan
terraform apply
```

This creates: GuardDuty, Security Hub (CIS + FSBP), CloudTrail, AWS Config + rules

**3. Org SCPs:**

First enable SCPs in console: **Organizations → Policies → Service Control Policies → Enable**

```bash
cd terraform/org
terraform init
terraform plan
terraform apply
```

This creates: 4 SCPs attached to both OUs

### Phase 6 — OIDC Thumbprint (Important)

The GitHub Actions OIDC thumbprint must match the current certificate. Get the correct thumbprint by running:

```bash
openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 < /dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha1 -noout \
  | sed 's/SHA1 Fingerprint=//g' \
  | sed 's/://g' \
  | tr '[:upper:]' '[:lower:]'
```

Update the output in `terraform/workload/main.tf`:

```hcl
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["<output from command above>"]
}
```

Then `terraform apply` to update.

### Phase 7 — Build and Push App Images

**Backend:**

```bash
cd app/backend
npm install
npx tsc
./deploy.sh
```

**Frontend:**

```bash
cd app/frontend
npm install
npm run build
./deploy.sh
```

**Force ECS redeployment:**

```bash
# Backend
aws ecs update-service \
  --cluster poc-aws-workload-cluster \
  --service poc-aws-workload-backend \
  --force-new-deployment \
  --region ap-southeast-2 \
  --profile poc-workload

# Frontend
aws ecs update-service \
  --cluster poc-aws-workload-cluster \
  --service poc-aws-workload-frontend \
  --force-new-deployment \
  --region ap-southeast-2 \
  --profile poc-workload
```

### Phase 8 — GitHub Actions Setup

1. Go to your GitHub repo → **Settings → Secrets and variables → Actions → Variables**
2. Add repository variable:
   - Name: `AWS_ACCOUNT_ID`
   - Value: `129264xxxxxx` (your `poc-workload` account ID)

3. The workflows trigger automatically on push to `main` when files under `app/backend/**` or `app/frontend/**` change.

4. To trigger manually, go to **Actions → Backend Deploy / Frontend Deploy → Run workflow**

---

## Application Endpoints

| Service      | URL                                                                       |
| ------------ | ------------------------------------------------------------------------- |
| App          | `http://<alb-dns>`                                                       |
| Health Check | `http://<alb-dns>/health`                                                 |
| Tasks API    | `http://<alb-dns>/api/tasks`                                              |

---

## API Endpoints

| Method | Path         | Description                     |
| ------ | ------------ | ------------------------------- |
| `GET`  | `/health`    | Health check (ALB target group) |
| `GET`  | `/api/tasks` | List all tasks                  |
| `POST` | `/api/tasks` | Create a task                   |

---

## CI/CD Pipeline

GitHub Actions workflows use **OIDC** — no static AWS access keys stored in GitHub.

```
Push to main (app/backend/** or app/frontend/**)
  → Configure AWS credentials via OIDC
  → Login to ECR
  → Docker build + tag with git SHA
  → Push image to ECR
  → ECS update-service (rolling deploy)
  → Wait for services-stable
```

**Trust relationship note:** GitHub embeds immutable owner/repo IDs in the OIDC `sub` claim. Use this format in the trust condition:

```
repo:username@ownerID/reponame@repoID:*
```

Get your IDs from the CloudTrail event on a failed OIDC attempt, or from the GitHub API.

---

## Code & Security Scanning

Four automated scans run in GitHub Actions:

| Workflow            | Tool    | Trigger                          | What it checks                                    |
| -------------------- | ------- | --------------------------------- | -------------------------------------------------- |
| `codeql.yaml`         | CodeQL  | push/PR to `app/**`               | SAST on backend + frontend (JS/TS)                 |
| `iac-scan.yaml`       | tfsec   | push/PR to `terraform/**`         | AWS misconfigurations in Terraform                 |
| `secret-scan.yaml`    | gitleaks| every push/PR                     | Leaked credentials/keys in commits                 |
| `backend/frontend-deploy.yaml` | Trivy | build step, before ECR push | CRITICAL/HIGH CVEs in the built container image    |

**Private repo caveat:** CodeQL and tfsec both upload results via GitHub's code-scanning (SARIF) API, which requires **GitHub Advanced Security**. GHAS is free for public repos but is a paid add-on for private ones. While this repo is private, `codeql.yaml` and the SARIF-upload step in `iac-scan.yaml` will fail with `Resource not accessible by integration` — that's expected, not a bug. Both start working automatically once the repo is switched to public. Trivy and gitleaks are unaffected either way since they don't depend on that API.

---

## Troubleshooting

### SSO Token Expired

```bash
aws sso login --profile poc-management
```

This refreshes all profiles under the same SSO session.

### ECS Task Failing to Start

Check CloudWatch logs:

```
/ecs/poc-aws-workload/backend
/ecs/poc-aws-workload/frontend
```

### OIDC Authentication Failing

Get the correct thumbprint:

```bash
openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 < /dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha1 -noout \
  | sed 's/SHA1 Fingerprint=//g' \
  | sed 's/://g' \
  | tr '[:upper:]' '[:lower:]'
```

Check the trust relationship `sub` condition includes the correct repo owner and repo IDs.

### Terraform State Lock

If state is locked after a failed apply:

```bash
terraform force-unlock <lock-id>
```

---

## Cost Estimate (POC)

| Service                           | Estimated Cost    |
| --------------------------------- | ----------------- |
| ECS Fargate (2 services, minimal) | ~$15–20/month     |
| ALB                               | ~$20/month        |
| NAT Gateway                       | ~$35/month        |
| GuardDuty                         | ~$1–5/month       |
| Secrets Manager                   | ~$1/month         |
| CloudTrail                        | Free (1 trail)    |
| Security Hub                      | ~$5/month         |
| KMS                               | ~$1/month         |
| **Total**                         | **~$78–87/month** |

> **Tip:** Delete the ALB and set ECS desired count to 0 when not actively demoing to reduce costs significantly.

---

## References

- [AWS Organizations SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GuardDuty Organizations](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html)
- [Security Hub Standards](https://docs.aws.amazon.com/securityhub/latest/userguide/standards-reference.html)
- [Terraform S3 Backend Native Locking](https://developer.hashicorp.com/terraform/language/backend/s3)
- [ECS Fargate Networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html)
