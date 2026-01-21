package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/fer/gula-ai/internal/app"
	"github.com/fer/gula-ai/internal/ui"
)

const version = "0.1.0"

func main() {
	// Parse command line arguments
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--version", "-v":
			fmt.Printf("gula-ai version %s\n", version)
			os.Exit(0)
		case "--help", "-h":
			printHelp()
			os.Exit(0)
		}
	}

	// Ensure config directory exists
	if err := app.EnsureConfigDir(); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating config directory: %v\n", err)
		os.Exit(1)
	}

	// Load configuration
	cfg, err := app.LoadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	// Set working directory from current directory if not set
	if cfg.WorkingDir == "" {
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error getting current directory: %v\n", err)
			os.Exit(1)
		}
		cfg.WorkingDir = cwd
	}

	// Create and run the TUI
	model := ui.NewModel(cfg)
	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running application: %v\n", err)
		os.Exit(1)
	}
}

func printHelp() {
	fmt.Println(`gula-ai - AI Agent TUI

Usage:
  gula-ai [options]

Options:
  -h, --help     Show this help message
  -v, --version  Show version information

Keyboard Shortcuts:
  Enter          Send message
  Ctrl+N         New conversation
  Esc            Cancel request
  Ctrl+C         Quit

Configuration:
  Config file: ~/.config/gula-agent/config.json

Environment Variables:
  GULA_CONFIG_DIR  Override config directory location
  GULA_API_KEY     API key for authentication
  GULA_API_URL     Override API base URL`)
}
