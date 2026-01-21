package app

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Config holds the application configuration
type Config struct {
	APIBaseURL      string `json:"api_base_url"`
	APIKey          string `json:"api_key"`
	DefaultModel    string `json:"default_model"`
	ConversationID  string `json:"conversation_id,omitempty"`
	WorkingDir      string `json:"working_dir,omitempty"`
	RAGEnabled      bool   `json:"rag_enabled"`
	MaxTokens       int    `json:"max_tokens,omitempty"`
	Temperature     float64 `json:"temperature,omitempty"`
}

// DefaultConfig returns a config with sensible defaults
func DefaultConfig() *Config {
	return &Config{
		APIBaseURL:   "http://localhost:8000",
		DefaultModel: "claude-sonnet",
		RAGEnabled:   true,
		MaxTokens:    4096,
		Temperature:  0.7,
	}
}

// ConfigDir returns the path to the config directory
func ConfigDir() (string, error) {
	// Check for GULA_CONFIG_DIR environment variable first
	if dir := os.Getenv("GULA_CONFIG_DIR"); dir != "" {
		return dir, nil
	}

	// Default to ~/.config/gula-agent
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "gula-agent"), nil
}

// ConfigPath returns the path to the config file
func ConfigPath() (string, error) {
	dir, err := ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "config.json"), nil
}

// LoadConfig loads the configuration from the config file
func LoadConfig() (*Config, error) {
	configPath, err := ConfigPath()
	if err != nil {
		return DefaultConfig(), nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultConfig(), nil
		}
		return nil, err
	}

	config := DefaultConfig()
	if err := json.Unmarshal(data, config); err != nil {
		return nil, err
	}

	// Override with environment variables if set
	if apiKey := os.Getenv("GULA_API_KEY"); apiKey != "" {
		config.APIKey = apiKey
	}
	if apiURL := os.Getenv("GULA_API_URL"); apiURL != "" {
		config.APIBaseURL = apiURL
	}

	return config, nil
}

// SaveConfig saves the configuration to the config file
func SaveConfig(config *Config) error {
	configPath, err := ConfigPath()
	if err != nil {
		return err
	}

	// Ensure directory exists
	dir := filepath.Dir(configPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0644)
}

// GetWorkingDir returns the current working directory for the agent
func (c *Config) GetWorkingDir() string {
	if c.WorkingDir != "" {
		return c.WorkingDir
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "."
	}
	return cwd
}
