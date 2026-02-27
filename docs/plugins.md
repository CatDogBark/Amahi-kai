# Architecture

Amahi-kai is a monolithic Rails application. The legacy plugin/engine architecture was removed in v0.1.3.

## Structure

All controllers, models, and views live in the standard Rails directories:

| Area | Controller | Routes |
|------|-----------|--------|
| Users | `UsersController` | `/users` |
| Shares | `SharesController` | `/shares` |
| Disks | `DisksController` | `/disks/*` |
| Apps | `AppsController` | `/apps/*` |
| Network | `NetworkController` | `/network/*` |
| Settings | `SettingsController` | `/settings/*` |
| File Browser | `FileBrowserController` | `/files/:share_id/*` |
| Setup Wizard | `SetupController` | `/setup/*` |
| Dashboard | `FrontController` | `/` |

## Services

Business logic is extracted into service objects:

- `ShareFileSystem` — directory creation, permissions, cleanup
- `SambaService` — Samba configuration generation and deployment
- `ShareAccessManager` — user access control for shares

## Libraries

System integration lives in `lib/`:

- `Shell` — command execution with auto-sudo and dummy mode
- `DiskManager` — drive detection, formatting, mounting
- `Greyhole` — storage pool configuration
- `CloudflareService` — tunnel management
- `SecurityAudit` — security scanning and auto-fix
- `DashboardStats` — system metrics collection
