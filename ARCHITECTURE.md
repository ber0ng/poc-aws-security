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

    subgraph AWS_ORG["AWS Organizations (o-zaq1dq95ss)"]
        direction TB

        subgraph MGMT["Management Account (835107812500)"]
            direction TB
            SSO["IAM Identity Center\nSSO Portal"]
            S3_STATE["S3 Bucket\nveron-poc-tfstate\nTerraform State"]
            subgraph SCPS["Service Control Policies"]
                SCP1["DenyDisableCloudTrail"]
                SCP2["DenyDisableGuardDuty"]
                SCP3["DenyPublicS3"]
                SCP4["DenyLeaveOrganization"]
            end
        end

        subgraph SEC_OU["Security OU"]
            subgraph SEC_ACC["poc-security Account (962635286921)"]
                direction TB
                GD["GuardDuty\nThreat Detection"]
                SH["Security Hub\nCIS v1.4 + FSBP"]
                CT["CloudTrail\nOrg-level Trail\nLog Validation"]
                CFG["AWS Config\nCompliance Rules"]
                S3_CT["S3 Bucket\nCloudTrail Logs"]
            end
        end

        subgraph WL_OU["Workloads OU"]
            subgraph WL_ACC["poc-workload Account (129264592348)"]
                direction TB
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
    WL_ACC -.->|"findings"| GD
    WL_ACC -.->|"findings"| SH
    WL_ACC -.->|"API logs"| CT
    CT --> S3_CT
    WL_ACC -.->|"config changes"| CFG

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

    class GD,SH,CT,CFG,KMS,SM,OIDC,GH_ROLE security
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

```
poc-workload account
  ├── API calls → CloudTrail → S3 (log file validation)
  ├── Threats → GuardDuty → findings dashboard
  ├── Config changes → AWS Config → compliance rules evaluation
  └── All findings → Security Hub (CIS v1.4 + FSBP standards)
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
Root (r-vlhs)
├── Security OU (ou-vlhs-jiyreru5)
│   └── poc-security (962635286921)
│       ├── GuardDuty
│       ├── Security Hub
│       ├── CloudTrail
│       └── AWS Config
└── Workloads OU (ou-vlhs-nh1mlscc)
    └── poc-workload (129264592348)
        ├── VPC + Networking
        ├── ECS Fargate Cluster
        ├── ECR Repositories
        ├── ALB
        ├── KMS + Secrets Manager
        └── GitHub Actions OIDC

Management Account (835107812500)
├── IAM Identity Center (SSO)
├── Terraform State (S3)
└── Service Control Policies → applied to both OUs
```
