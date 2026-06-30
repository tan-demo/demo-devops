# staging (placeholder)

Reserved environment. To wire it, copy `../dev/root.hcl` and the per-component `terragrunt.hcl`
units, then adjust the locals in `root.hcl` (`cluster_name`, `vpc_cidr`, larger node groups, the
`cloudflare` block, etc.). The reusable modules live in `../../modules`, so no resource code is
duplicated — only the `root.hcl` locals change.

Left unwired on purpose: Part 5 is validate-only and only **dev** is exercised.
