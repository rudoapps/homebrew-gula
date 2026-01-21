package tools

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

// WriteFileTool writes content to a file
type WriteFileTool struct {
	workingDir string
}

func (t *WriteFileTool) Name() string {
	return "write_file"
}

func (t *WriteFileTool) Description() string {
	return "Write content to a file (creates or overwrites)"
}

func (t *WriteFileTool) NeedsApproval() bool {
	return true // Always requires user approval
}

func (t *WriteFileTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get path argument
	pathArg, ok := args["path"]
	if !ok {
		return "", fmt.Errorf("missing required argument: path")
	}
	path, ok := pathArg.(string)
	if !ok {
		return "", fmt.Errorf("path must be a string")
	}

	// Get content argument
	contentArg, ok := args["content"]
	if !ok {
		return "", fmt.Errorf("missing required argument: content")
	}
	content, ok := contentArg.(string)
	if !ok {
		return "", fmt.Errorf("content must be a string")
	}

	// Resolve path relative to working directory
	if !filepath.IsAbs(path) {
		path = filepath.Join(t.workingDir, path)
	}

	// Ensure parent directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create directory: %w", err)
	}

	// Check if file exists (for reporting)
	existed := true
	if _, err := os.Stat(path); os.IsNotExist(err) {
		existed = false
	}

	// Write the file
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		return "", fmt.Errorf("failed to write file: %w", err)
	}

	if existed {
		return fmt.Sprintf("File updated: %s (%d bytes)", path, len(content)), nil
	}
	return fmt.Sprintf("File created: %s (%d bytes)", path, len(content)), nil
}

// FormatForApproval formats the tool execution for user approval
func (t *WriteFileTool) FormatForApproval(args map[string]interface{}) string {
	path, _ := args["path"].(string)
	content, _ := args["content"].(string)

	preview := content
	if len(preview) > 500 {
		preview = preview[:500] + "\n... (truncated)"
	}

	return fmt.Sprintf("Write to file: %s\n\nContent:\n%s", path, preview)
}
