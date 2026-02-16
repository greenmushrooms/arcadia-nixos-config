# Arcadia NixOS Config

Media center NixOS configuration with CI/CD deployment via GitHub Actions.

## TODO

- [ ] Enable firewall with allowed ports only (SSH 22, media service ports) 
- [x] Fix deprecated `services.logind.lidSwitch` warning
- [ ] Consider branch protection rules on GitHub for safety
- [ ] Add `nixos-rebuild dry-run` step to workflow before actual switch
- [ ] Remove old `~/actions-runner` directory (no longer needed)
- [ ] Set up git credential cache expiry / rotate PAT periodically
