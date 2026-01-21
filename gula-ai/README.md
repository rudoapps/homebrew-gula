# gula-ai

A rich Terminal User Interface (TUI) for the Gula AI agent, built with Go and [Bubble Tea](https://github.com/charmbracelet/bubbletea).

## Features

- **Rich TUI Interface**: Chat panel, tools panel, and status bar
- **SSE Streaming**: Real-time streaming responses from the AI agent
- **Local Tool Execution**: Execute tools locally with approval workflow
- **Keyboard-Driven**: Full keyboard navigation with vim-like bindings
- **Project Context**: Automatic project type detection and code search

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/fer/gula-ai.git
cd gula-ai

# Build
make build

# Run
./bin/gula-ai
```

### Via Homebrew (with gula)

```bash
brew install fer/tap/gula
gula ai
```

## Usage

```bash
# Run directly
gula-ai

# Or via gula command
gula ai

# Show help
gula-ai --help

# Show version
gula-ai --version
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Send message |
| `Ctrl+N` | New conversation |
| `Ctrl+T` | Toggle tools panel |
| `Ctrl+S` | List sessions |
| `Ctrl+M` | Change model |
| `Tab` | Switch panel focus |
| `↑/k`, `↓/j` | Scroll up/down |
| `?` | Show help |
| `Esc` | Cancel/unfocus |
| `Ctrl+C` | Quit |

## Configuration

Configuration is stored in `~/.config/gula-agent/config.json`:

```json
{
  "api_base_url": "http://localhost:8000",
  "api_key": "your-api-key",
  "default_model": "claude-sonnet",
  "rag_enabled": true,
  "max_tokens": 4096,
  "temperature": 0.7
}
```

### Environment Variables

- `GULA_CONFIG_DIR`: Override config directory location
- `GULA_API_KEY`: API key for authentication
- `GULA_API_URL`: Override API base URL

## Local Tools

The following tools can be executed locally:

| Tool | Description | Requires Approval |
|------|-------------|-------------------|
| `read_file` | Read file contents | No |
| `write_file` | Write to a file | **Yes** |
| `list_files` | List directory contents | No |
| `search_code` | Search code with regex | No |
| `run_command` | Execute shell command | **Yes** |
| `git_info` | Get git repository info | No |

## Development

```bash
# Install dependencies
make deps

# Run tests
make test

# Run with hot reload (requires air)
air

# Format code
make fmt

# Run linter
make lint

# Build release binaries
make release
```

## Architecture

```
gula-ai/
├── cmd/gula-ai/          # Entry point
├── internal/
│   ├── app/              # Application config and initialization
│   ├── ui/               # Bubble Tea UI components
│   │   ├── model.go      # Main application model
│   │   ├── update.go     # Message handlers
│   │   ├── view.go       # Rendering
│   │   ├── keymap.go     # Keyboard shortcuts
│   │   └── styles.go     # Lipgloss styles
│   ├── api/              # API client and SSE parsing
│   ├── tools/            # Local tool implementations
│   └── context/          # Project detection and tree generation
├── Makefile
└── README.md
```

## License

MIT
