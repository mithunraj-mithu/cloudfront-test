# ADR-0001: Alamy Labs Infrastructure Guidelines

## Status
Accepted — 2026-02-11 (Updated 2026-04-14)

## Context
This document outlines the standard operational structure for the Alamy Labs (`labs.alamy.com`) infrastructure repository. This environment acts as a reverse proxy router to various external Proof of Concept (POC) applications hosted on PaaS (Platform as a Service) providers like Vercel, Netlify, or Bolt. 

Terraform runs exclusively via GitHub Actions CI/CD pipelines. Manual executions are prohibited to maintain state integrity.

## Decision

### 1. File Layout
- **Flat structure** inside the `terraform/` directory. 
- Files are named by their AWS service or logical purpose (e.g., `cloudfront.tf`, `acm.tf`, `r53.tf`). We do not use a monolithic `main.tf` file.

### 2. State & Environment Management
- **Workspaces + Per-Environment Configs:** Isolated state files. Backend configurations (`backends/*.conf`) separate the S3 state storage, and variable files (`workspaces/*.tfvars`) inject environment-specific variables.
- **S3 Backend Configuration:** State is stored in Amazon S3 with AES-256 server-side encryption enabled. State locking is handled via an Amazon DynamoDB table.

### 3. Execution & Dependencies
- **Pessimistic Provider Constraints:** Provider versions are locked using the pessimistic constraint operator (e.g., `~> 5.52.0`). This allows minor patch updates for security but blocks major versions.
- **No Local `.terraform.lock.hcl`:** The CI pipeline runs `terraform init -upgrade` to resolve the provider dependency tree dynamically based on the pessimistic constraints.

### 4. Security & Compliance
- **Strict TLS Standards:** All CloudFront viewer certificates and origin connections enforce `TLSv1.2` as the minimum protocol. `TLSv1.1` and older are explicitly rejected.
- **IAM Best Practices:** The infrastructure relies entirely on Assumed Roles (`sts:AssumeRole`) and Instance Profiles. We do not provision IAM Users or generate static access keys.

## Adding a New Application
To add a new POC application to the Labs router:
1. Open the target environment's variable file (e.g., `production.tfvars`).
2. Add a new key-value pair to the `labs_applications` map block.
3. Commit and push. The pipeline will dynamically create a new CloudFront Origin and Cache Behavior route.