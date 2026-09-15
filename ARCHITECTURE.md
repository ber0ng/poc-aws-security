# AWS Security POC — Architecture

This document describes the end-to-end architecture of the AWS Security POC, built to demonstrate ISO 27001-aligned cloud infrastructure.

---

## Architecture Diagram

```mermaid
flowchart TB
    subgraph DEV["👩‍💻 Developer"]
        direction TB
        LOCAL["Local Machine\nAWS CLI + Terraform"]
        VSCODE["VS Code\nTypeScript App"]
    end

    subgraph GH["GitHub"]
        direction TB
        REPO["poc-aws-security\nRepository"]
        subgraph ACTIONS["GitHub Actions (OIDC — no static keys)"]
            BE_WF["backend-deploy.yml"]
            FE_WF["frontend-deploy.yml"]
        end
    end

    subgraph AWS_ORG["AWS Organizations (o-xxxxxxxxxx)"]
        direction TB

        subgraph MGMT["Management Account (835107xxxxxx)"]
            direction TB
            SSO["IAM Identity Center\nSSO Portal"]
            S3_STATE["S3 Bucket\nTerraform State"]
            CT["CloudTrail\nOrganization Trail\n(is_organization_trail=true)\nLog Validation"]
            GD_ADMIN["GuardDuty\nOrganization Admin\nDelegation"]
            subgraph SCPS["Service Control Policies"]
                SCP1["DenyDisableCloudTrail"]
                SCP2["DenyDisableGuardDuty"]
                SCP3["DenyPublicS3"]
                SCP4["DenyLeaveOrganization"]
            end
        end

        subgraph SEC_OU["Security OU"]
            subgraph SEC_ACC["poc-security Account (962635xxxxxx)"]
                direction TB
                GD["GuardDuty\nDelegated Admin\nThreat Detection\n(org rollup, auto_enable=ALL)"]
                SH["Security Hub\nCIS v1.4 + FSBP"]
                CFG["AWS Config\nCompliance Rules"]
                S3_CT["S3 Bucket\nCloudTrail Logs\n(AWSLogs/org-id/account-id/...)"]
            end
        end

        subgraph WL_OU["Workloads OU"]
            subgraph WL_ACC["poc-workload Account (129264xxxxxx)"]
                direction TB
                GD_MEMBER["GuardDuty Member\n(auto-enrolled)"]
                subgraph VPC["VPC (10.0.0.0/16)"]
                    direction TB
                    subgraph PUBLIC["Public Subnets"]
                        ALB["Application\nLoad Balancer\nHTTP:80"]
                        NGW["NAT Gateway"]
                    end
                    subgraph PRIVATE["Private Subnets"]
                        subgraph ECS["ECS Fargate Cluster"]
                            FE_SVC["Frontend Service\nReact/TypeScript\nPort 80"]
                            BE_SVC["Backend Service\nNode.js/TypeScript\nPort 3000"]
                        end
                    end
                end
                ECR_BE["ECR\npoc-aws-workload-backend\nScan on Push"]
                ECR_FE["ECR\npoc-aws-workload-frontend\nScan on Push"]
                KMS["KMS CMK\nEncryption Key"]
                SM["Secrets Manager\nApp Secrets\nEncrypted by KMS"]
                CW["CloudWatch\nContainer Logs"]
                OIDC["OIDC Provider\ntoken.actions.githubusercontent.com"]
                GH_ROLE["IAM Role\ngithub-actions-role\nECR + ECS access"]
            end
        end
    end

    subgraph USERS["Users (IAM Identity Center)"]
        direction LR
        ADMIN["veron-admin-security\nSecurity Admin Group"]
        WL_ADMIN["veron-admin-workload\nWorkloads Admin Group"]
        GEN["alice / bob / carol / marky\nGeneral Users Group\nRead-only"]
    end

    %% Developer flows
    LOCAL -->|"aws sso login\n--profile poc-management"| SSO
    LOCAL -->|"terraform apply"| S3_STATE
    VSCODE -->|"git push"| REPO

    %% GitHub Actions OIDC flow
    REPO --> ACTIONS
    ACTIONS -->|"AssumeRoleWithWebIdentity\n(OIDC)"| OIDC
    OIDC --> GH_ROLE
    BE_WF -->|"docker push"| ECR_BE
    FE_WF -->|"docker push"| ECR_FE
    BE_WF -->|"ecs update-service"| BE_SVC
    FE_WF -->|"ecs update-service"| FE_SVC

    %% Traffic flow
    INTERNET(("🌐 Internet")) -->|"HTTP:80"| ALB
    ALB -->|"/api/* → Port 3000"| BE_SVC
    ALB -->|"/ → Port 80"| FE_SVC
    BE_SVC -->|"pull secret"| SM
    SM -->|"decrypt"| KMS
    BE_SVC --> CW
    FE_SVC --> CW
    ECS -->|"outbound via"| NGW

    %% ECR to ECS
    ECR_BE -->|"pull image"| BE_SVC
    ECR_FE -->|"pull image"| FE_SVC

    %% Security monitoring
    WL_ACC -.->|"member findings\n(auto-enrolled)"| GD
    WL_ACC -.->|"findings"| SH
    WL_ACC -.->|"API events\n(org trail)"| CT
    CT -->|"log delivery"| S3_CT
    WL_ACC -.->|"config changes"| CFG
    GD_ADMIN -.->|"delegates admin to"| SEC_ACC

    %% SCPs applied to OUs
    SCPS -.->|"applied to"| SEC_OU
    SCPS -.->|"applied to"| WL_OU

    %% User SSO access
    USERS -->|"SSO Portal"| SSO
    SSO -->|"AdministratorAccess"| WL_ACC
    SSO -->|"AdministratorAccess"| SEC_ACC
    SSO -->|"ReadOnlyAccess"| WL_ACC

    %% Styling
    classDef security fill:#DD344C,color:#fff,stroke:#DD344C
    classDef network fill:#8C4FFF,color:#fff,stroke:#8C4FFF
    classDef app fill:#1A9C3E,color:#fff,stroke:#1A9C3E
    classDef github fill:#24292E,color:#fff,stroke:#24292E
    classDef user fill:#0066CC,color:#fff,stroke:#0066CC

    class GD,GD_ADMIN,GD_MEMBER,SH,CT,CFG,KMS,SM,OIDC,GH_ROLE security
    class ALB,NGW network
    class FE_SVC,BE_SVC,ECR_BE,ECR_FE app
    class REPO,ACTIONS,BE_WF,FE_WF github
    class ADMIN,WL_ADMIN,GEN user
```

---

## Traffic Flow

```
Internet
  └── ALB (HTTP:80, public subnet)
        ├── / and /* → Frontend Service (ECS Fargate, private subnet, port 80)
        └── /api/* and /health → Backend Service (ECS Fargate, private subnet, port 3000)
                                      └── Secrets Manager (via VPC, KMS decrypt)
                                      └── CloudWatch Logs
```

---

## CI/CD Flow

```
Developer pushes to main
  └── GitHub Actions triggered (path filter: app/backend/** or app/frontend/**)
        └── OIDC token issued by GitHub
              └── AWS STS AssumeRoleWithWebIdentity
                    └── github-actions-role (ECR + ECS permissions)
                          ├── Docker build + tag with git SHA
                          ├── Push to ECR (scan on push)
                          └── ECS update-service (rolling deploy)
                                └── Wait for services-stable
```

---

## Security Monitoring Flow

CloudTrail and GuardDuty are both centralized via delegated administration, not
per-account standalone resources — every OU member account's activity rolls
up into the security account (or, for the trail itself, is delivered there).

```
Management account
  └── CloudTrail organization trail (is_organization_trail=true)
        — auto-applies to every account in every OU —
        └── log delivery → S3 bucket owned by poc-security account
  └── GuardDuty organization admin delegation → poc-security account

poc-security account (delegated admin)
  ├── GuardDuty — auto_enable_organization_members=ALL
  │     └── poc-workload (and every other OU account) auto-enrolled as a member
  │           → findings roll up here, not siloed per account
  ├── Security Hub (CIS v1.4 + FSBP standards)
  ├── AWS Config → compliance rules evaluation
  └── S3 bucket → receives CloudTrail logs from every account:
        AWSLogs/<org-id>/<account-id>/CloudTrail/...

poc-workload account
  ├── API calls → captured by the org trail → delivered to security account's S3
  ├── Threats → GuardDuty member detector (auto-managed) → findings visible in poc-security
  └── Config changes → AWS Config (security account) → compliance rules evaluation
```

---

## Network Layout

```
VPC: 10.0.0.0/16
├── Public Subnets (ap-southeast-2a, ap-southeast-2b)
│   ├── Application Load Balancer
│   └── NAT Gateway (outbound for private subnets)
└── Private Subnets (ap-southeast-2a, ap-southeast-2b)
    └── ECS Fargate Tasks
        ├── Frontend (no public IP)
        └── Backend (no public IP)
```

---

## Account & OU Structure

```
Root
├── Security OU
│   └── poc-security (962635xxxxxx) — GuardDuty delegated admin
│       ├── GuardDuty (org rollup, auto-enable=ALL)
│       ├── Security Hub
│       ├── S3 bucket — receives CloudTrail logs from every account
│       └── AWS Config
└── Workloads OU
    └── poc-workload (129264xxxxxx) — GuardDuty member (auto-enrolled)
        ├── VPC + Networking
        ├── ECS Fargate Cluster
        ├── ECR Repositories
        ├── ALB
        ├── KMS + Secrets Manager
        └── GitHub Actions OIDC

Management Account (835107xxxxxx)
├── IAM Identity Center (SSO)
├── Terraform State (S3)
├── CloudTrail organization trail (is_organization_trail=true)
├── GuardDuty organization admin delegation → poc-security
└── Service Control Policies → applied to both OUs
```

## Screenshots
