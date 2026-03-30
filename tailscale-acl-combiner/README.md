# Tailscale ACL Combiner

This directory contains modular Tailscale ACL configurations split by environment and concern.

## Structure

```
tailscale-acl-combiner/
├── production/
│   ├── groups.json       # Production groups and tag owners
│   ├── ipsets.json       # Production IP sets and host definitions
│   └── posture.json      # Production device posture rules
├── development/
│   ├── groups.json       # Development groups and tag owners
│   ├── ipsets.json       # Development IP sets and host definitions
│   └── posture.json      # Development device posture rules
└── README.md
```

## File Descriptions

### groups.json
Defines user groups, device tag groups, and tag ownership. This controls:
- Who belongs to which logical groups
- Which devices are grouped by tags
- Who can assign specific tags to devices

### ipsets.json
Defines named IP ranges and CIDR blocks. These can be referenced in ACL rules instead of hardcoding IP addresses, making rules more maintainable.

### posture.json
Defines device posture checks that can be used as conditions in ACL rules. Posture checks can verify:
- Operating system type
- Tailscale version currency
- Disk encryption status
- Release track (stable/unstable)

## Usage

### Automated Workflow (Recommended)

1. Create a new branch for your ACL changes:
   ```bash
   git checkout -b update-acl-rules
   ```

2. Edit the modular files in either `production/` or `development/`:
   - `groups.json` - Modify user groups and tag owners
   - `ipsets.json` - Update IP sets and host definitions
   - `posture.json` - Change device posture requirements

3. Commit and push your changes:
   ```bash
   git add tailscale-acl-combiner/
   git commit -m "Update ACL rules for [environment]"
   git push origin update-acl-rules
   ```

4. Run the GitHub Actions workflow:
   - Go to **Actions** → **Update ACL Policy from Modular Files**
   - Click **Run workflow**
   - Select your branch and environment (production/development)
   - The workflow will:
     - Combine the modular files into `policy.hujson`
     - Commit the changes
     - Create a PR for review

5. Review and merge the PR:
   - Check the generated `policy.hujson` changes
   - The existing CI will run ACL tests
   - Merge to deploy to Tailscale

### Manual Combiner Usage

You can also run the combiner script locally:

```bash
cd tailscale-acl-combiner
python3 combine.py production   # or 'development'
```

This will read the modular files and update `../policy.hujson` in place.

## Combiner Output

The combiner merges modular files into a single policy structure:

```javascript
{
  "grants": [ /* preserved from existing policy.hujson */ ],
  "ssh": [ /* preserved from existing policy.hujson */ ],
  "autoApprovers": { /* preserved from existing policy.hujson */ },
  "groups": { /* from groups.json */ },
  "tagOwners": { /* from groups.json */ },
  "hosts": { /* from ipsets.json */ },
  "postures": { /* from posture.json */ }
}
```

**Note**: The combiner preserves `grants`, `ssh`, and `autoApprovers` sections from the existing `policy.hujson` file, only updating the modular sections.

## Environment Differences

**Production:**
- Stricter device posture requirements
- More granular access controls
- Separate admin and developer groups
- Specific tag ownership restrictions

**Development:**
- More permissive posture rules
- Broader team access
- Simplified group structure
- Faster iteration for testing
