# Coder Templates

A collection of [Coder](https://coder.com) workspace templates for cloud development environments.

## Available Templates

| Template | Description |
|----------|-------------|
| [devpod](./devpod) | Kubernetes-based development workspace with Docker, tmux, Claude Code, and more |

## Usage

### Import via Coder UI

1. Go to **Templates** → **Create Template**
2. Select **From Git Repository**
3. Enter repository URL: `https://github.com/jedarden/coder-templates`
4. Select the template directory (e.g., `devpod`)

### Import via CLI

```bash
# Clone this repository
git clone https://github.com/jedarden/coder-templates.git
cd coder-templates

# Create a template
coder templates create devpod --directory ./devpod

# Or update an existing template
coder templates push devpod --directory ./devpod
```

## Template Structure

Each template follows the standard Coder template structure:

```
template-name/
├── main.tf           # Terraform configuration
├── install-tools.sh  # Startup/provisioning scripts
└── README.md         # Template documentation
```

## Contributing

1. Create a new directory for your template
2. Add `main.tf` with Coder/Terraform resources
3. Add any supporting scripts
4. Add a `README.md` documenting the template
5. Submit a pull request

## License

MIT
