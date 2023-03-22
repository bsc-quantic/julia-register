# julia-register

_A GitHub action to register Julia packages in federated registries._

You can think of it as the official [Register Julia Package](https://github.com/marketplace/actions/register-julia-package) action but for private registries.

## Options

### Inputs

- `registry`: GitHub URL to the private registry.
- `push`: If `true`, push the branch to the registry. Defaults to `true`.
  - NOTE Be sure that the used `GITHUB_TOKEN` has the needed permissions.
- `branch`: Optional. If `inputs.push=true`, branch name where the registering package will be uploaded.
- `botname`: Name of the registering user. Defaults to `github-actions[bot]`.
- `botemail`: Email of the registering user. Defaults to `41898282+github-actions[bot]@users.noreply.github.com`.

### Outputs

- `name`: Project name.
- `uuid`: Project UUID.
- `version`: Project version.
- `hash`: Tree hash of the registering package.
- `branch`: If `inputs.push=true`, branch where the registering package has been uploaded.
- `path`: Path to the locally cloned Git repository of the private registry.

## Example workflow

```yaml
name: Register Package
on:
  workflow_dispatch:
jobs:
  register:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: julia-actions/setup-julia@v1
      - uses: bsc-quantic/julia-register@v0.1
        with:
          registry: https://github.com/YOUR_ORGANIZATION/YOUR_REGISTRY_REPO
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
