# Architecture Overview

## Design Principles

1. **Module-first**: All infrastructure is provisioned through reusable, tested modules
2. **Environment parity**: Dev, staging, and prod use identical modules with different variables
3. **Least privilege**: RBAC assignments codified; no portal-created permissions
4. **Immutable infrastructure**: Changes flow through CI/CD, never manual portal edits
5. **Observable by default**: All resources emit diagnostics to Log Analytics

## Module Dependency Graph

```
                    ┌──────────┐
                    │  naming  │
                    └────┬─────┘
                         │
                ┌────────┴────────┐
                ▼                 ▼
        ┌──────────────┐  ┌─────────────┐
        │resource-group│  │ common tags │
        └──────┬───────┘  └──────┬──────┘
               │                 │
       ┌───────┴──────────┬──────┘
       ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌───────────────┐
│virtual-network│ │log-analytics │  │managed-identity│
└──────┬───────┘  └──────┬───────┘  └───────┬───────┘
       │                 │                   │
       ▼                 │                   ▼
┌──────────┐             │          ┌────────────────┐
│  subnet  │             │          │rbac-assignment  │
└────┬─────┘             │          └────────────────┘
     │                   │
     ├────────┐          │
     ▼        ▼          │
┌────────┐ ┌──────────┐  │
│  nsg   │ │private-ep│  │
└────────┘ └──────────┘  │
                         │
    ┌────────────────────┤
    ▼                    ▼
┌───────────┐  ┌───────────┐  ┌─────────────────┐
│ key-vault │  │storage-acc│  │  aks-cluster     │
└───────────┘  └───────────┘  └─────────────────┘
```

## State Management

- **Backend**: Azure Storage Account with blob lease locking
- **Isolation**: One state file per environment
- **Cross-environment**: Data source lookups (not `terraform_remote_state`) to minimize coupling
- **Recovery**: Soft delete (30 days) + versioning on state storage account

## Environment Promotion Flow

```
Feature Branch → PR → Module CI (validate + lint + test)
                       ↓
                  Merge to main
                       ↓
              Dev: auto-plan → auto-apply
                       ↓
           Staging: plan → manual approval → apply
                       ↓
             Prod: plan → 2-approver gate → apply
```

## Network Topology

```
┌─────────────────────────────────────┐
│         Virtual Network             │
│         10.0.0.0/16                 │
│                                     │
│  ┌──────────────┐  ┌─────────────┐  │
│  │ AKS Subnet   │  │ Services    │  │
│  │ 10.0.0.0/22  │  │ 10.0.4.0/24│  │
│  └──────────────┘  └─────────────┘  │
│                                     │
│  ┌──────────────┐  ┌─────────────┐  │
│  │ Private EP   │  │ App GW      │  │
│  │ 10.0.5.0/24  │  │ 10.0.6.0/24│  │
│  └──────────────┘  └─────────────┘  │
└─────────────────────────────────────┘
```

## Security Model

| Layer | Approach |
|-------|----------|
| Authentication | Workload Identity Federation (OIDC) for CI/CD |
| Authorization | RBAC assignments as code with custom roles |
| Secrets | Azure Key Vault with RBAC access model |
| Network | Private endpoints for Storage/Key Vault; NSGs on all subnets |
| Policy | Azure Policy enforces tagging, HTTPS, public access restrictions |
| State | Encrypted at rest, locked during operations, soft-delete enabled |
