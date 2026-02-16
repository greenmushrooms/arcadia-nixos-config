# Arcadia NixOS Config

Media center NixOS configuration with CI/CD deployment via GitHub Actions.

## CI/CD Pipeline

```
feature branch → nix flake check
dev branch     → full nixos-rebuild build → auto PR to main
main branch    → nixos-rebuild switch (deploy)
```

Branch protection: `dev` requires flake check on PRs, `main` requires PR (no direct push).

## TODO

- [ ] Set up git credential cache expiry / rotate PAT periodically
- [ ] Split `configuration.nix` into modules (desktop, hardware, services) when it grows
