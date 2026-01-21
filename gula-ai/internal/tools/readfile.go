package tools

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ReadFileTool reads file contents
type ReadFileTool struct {
	workingDir string
}

func (t *ReadFileTool) Name() string {
	return "read_file"
}

func (t *ReadFileTool) Description() string {
	return "Read the contents of a file"
}

func (t *ReadFileTool) NeedsApproval() bool {
	return false
}

func (t *ReadFileTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get path argument
	pathArg, ok := args["path"]
	if !ok {
		return "", fmt.Errorf("missing required argument: path")
	}
	path, ok := pathArg.(string)
	if !ok {
		return "", fmt.Errorf("path must be a string")
	}

	// Resolve path relative to working directory
	if !filepath.IsAbs(path) {
		path = filepath.Join(t.workingDir, path)
	}

	// Check if file exists
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("file not found: %s", path)
		}
		return "", fmt.Errorf("error accessing file: %w", err)
	}

	if info.IsDir() {
		return "", fmt.Errorf("path is a directory, not a file: %s", path)
	}

	// Check file size (limit to 1MB)
	if info.Size() > 1024*1024 {
		return "", fmt.Errorf("file too large (>1MB): %s", path)
	}

	// Get optional line range arguments
	startLine := 1
	endLine := -1 // -1 means read to end

	if sl, ok := args["start_line"]; ok {
		if v, ok := sl.(float64); ok {
			startLine = int(v)
		}
	}
	if el, ok := args["end_line"]; ok {
		if v, ok := el.(float64); ok {
			endLine = int(v)
		}
	}

	// Read file
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("error opening file: %w", err)
	}
	defer file.Close()

	var lines []string
	scanner := bufio.NewScanner(file)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		if lineNum < startLine {
			continue
		}
		if endLine > 0 && lineNum > endLine {
			break
		}
		lines = append(lines, fmt.Sprintf("%4d | %s", lineNum, scanner.Text()))
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("error reading file: %w", err)
	}

	if len(lines) == 0 {
		return "(empty file or no lines in specified range)", nil
	}

	return strings.Join(lines, "\n"), nil
}
