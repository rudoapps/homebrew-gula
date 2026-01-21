package api

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// TokenInfo holds authentication token information
type TokenInfo struct {
	AccessToken  string    `json:"access_token"`
	TokenType    string    `json:"token_type"`
	ExpiresAt    time.Time `json:"expires_at,omitempty"`
	RefreshToken string    `json:"refresh_token,omitempty"`
}

// AuthManager handles authentication tokens
type AuthManager struct {
	tokenPath string
	token     *TokenInfo
}

// NewAuthManager creates a new auth manager
func NewAuthManager(configDir string) *AuthManager {
	return &AuthManager{
		tokenPath: filepath.Join(configDir, "token.json"),
	}
}

// LoadToken loads the token from disk
func (a *AuthManager) LoadToken() (*TokenInfo, error) {
	data, err := os.ReadFile(a.tokenPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var token TokenInfo
	if err := json.Unmarshal(data, &token); err != nil {
		return nil, err
	}

	a.token = &token
	return &token, nil
}

// SaveToken saves the token to disk
func (a *AuthManager) SaveToken(token *TokenInfo) error {
	data, err := json.MarshalIndent(token, "", "  ")
	if err != nil {
		return err
	}

	// Ensure directory exists
	dir := filepath.Dir(a.tokenPath)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}

	// Write with restricted permissions
	return os.WriteFile(a.tokenPath, data, 0600)
}

// GetToken returns the current token
func (a *AuthManager) GetToken() *TokenInfo {
	return a.token
}

// IsAuthenticated returns true if we have a valid token
func (a *AuthManager) IsAuthenticated() bool {
	if a.token == nil {
		return false
	}

	// Check if token is expired
	if !a.token.ExpiresAt.IsZero() && time.Now().After(a.token.ExpiresAt) {
		return false
	}

	return a.token.AccessToken != ""
}

// ClearToken removes the stored token
func (a *AuthManager) ClearToken() error {
	a.token = nil
	return os.Remove(a.tokenPath)
}
