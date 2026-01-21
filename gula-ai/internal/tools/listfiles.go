package tools

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ListFilesTool lists files in a directory
type ListFilesTool struct {
	workingDir string
}

func (t *ListFilesTool) Name() string {
	return "list_files"
}

func (t *ListFilesTool) Description() string {
	return "List files in a directory with optional pattern matching"
}

func (t *ListFilesTool) NeedsApproval() bool {
	return false
}

func (t *ListFilesTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get path argument (default to working directory)
	path := t.workingDir
	if pathArg, ok := args["path"]; ok {
		if p, ok := pathArg.(string); ok && p != "" {
			path = p
		}
	}

	// Resolve path relative to working directory
	if !filepath.IsAbs(path) {
		path = filepath.Join(t.workingDir, path)
	}

	// Get optional pattern argument
	pattern := "*"
	if patternArg, ok := args["pattern"]; ok {
		if p, ok := patternArg.(string); ok && p != "" {
			pattern = p
		}
	}

	// Get recursive flag
	recursive := false
	if recursiveArg, ok := args["recursive"]; ok {
		if r, ok := recursiveArg.(bool); ok {
			recursive = r
		}
	}

	// Check if path exists
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("directory not found: %s", path)
		}
		return "", fmt.Errorf("error accessing directory: %w", err)
	}

	if !info.IsDir() {
		return "", fmt.Errorf("path is not a directory: %s", path)
	}

	var files []string
	maxFiles := 1000 // Limit to prevent huge outputs

	if recursive {
		err = filepath.Walk(path, func(filePath string, info os.FileInfo, err error) error {
			if err != nil {
				return nil // Skip files we can't access
			}
			if len(files) >= maxFiles {
				return filepath.SkipAll
			}

			// Skip hidden directories
			if info.IsDir() && strings.HasPrefix(info.Name(), ".") && filePath != path {
				return filepath.SkipDir
			}

			// Match pattern
			if info.IsDir() {
				return nil
			}

			matched, _ := filepath.Match(pattern, info.Name())
			if matched {
				relPath, _ := filepath.Rel(path, filePath)
				if info.IsDir() {
					files = append(files, relPath+"/")
				} else {
					files = append(files, relPath)
				}
			}
			return nil
		})
	} else {
		entries, err := os.ReadDir(path)
		if err != nil {
			return "", fmt.Errorf("error reading directory: %w", err)
		}

		for _, entry := range entries {
			if len(files) >= maxFiles {
				break
			}

			matched, _ := filepath.Match(pattern, entry.Name())
			if matched {
				if entry.IsDir() {
					files = append(files, entry.Name()+"/")
				} else {
					files = append(files, entry.Name())
				}
			}
		}
	}

	if len(files) == 0 {
		return "(no files found matching pattern)", nil
	}

	// Sort files
	sort.Strings(files)

	result := strings.Join(files, "\n")
	if len(files) >= maxFiles {
		result += fmt.Sprintf("\n... (limited to %d files)", maxFiles)
	}

	return result, nil
}
