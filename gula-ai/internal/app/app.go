package app

import (
	"fmt"
	"os"
)

// App holds the application state and dependencies
type App struct {
	Config *Config
}

// New creates a new App instance
func New() (*App, error) {
	config, err := LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	return &App{
		Config: config,
	}, nil
}

// EnsureConfigDir ensures the config directory exists
func EnsureConfigDir() error {
	dir, err := ConfigDir()
	if err != nil {
		return err
	}
	return os.MkdirAll(dir, 0755)
}
