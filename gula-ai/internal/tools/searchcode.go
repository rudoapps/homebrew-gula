package tools

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// SearchCodeTool searches for patterns in code files
type SearchCodeTool struct {
	workingDir string
}

func (t *SearchCodeTool) Name() string {
	return "search_code"
}

func (t *SearchCodeTool) Description() string {
	return "Search for patterns in code files using regex"
}

func (t *SearchCodeTool) NeedsApproval() bool {
	return false
}

// Default file types to search
var defaultFileTypes = []string{
	".go", ".py", ".js", ".ts", ".jsx", ".tsx",
	".java", ".c", ".cpp", ".h", ".hpp",
	".rs", ".rb", ".php", ".swift", ".kt",
	".sh", ".bash", ".zsh",
	".json", ".yaml", ".yml", ".toml",
	".md", ".txt", ".sql",
}

func (t *SearchCodeTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get pattern argument
	patternArg, ok := args["pattern"]
	if !ok {
		return "", fmt.Errorf("missing required argument: pattern")
	}
	pattern, ok := patternArg.(string)
	if !ok {
		return "", fmt.Errorf("pattern must be a string")
	}

	// Compile regex
	re, err := regexp.Compile(pattern)
	if err != nil {
		return "", fmt.Errorf("invalid regex pattern: %w", err)
	}

	// Get path argument (default to working directory)
	searchPath := t.workingDir
	if pathArg, ok := args["path"]; ok {
		if p, ok := pathArg.(string); ok && p != "" {
			searchPath = p
		}
	}

	// Resolve path relative to working directory
	if !filepath.IsAbs(searchPath) {
		searchPath = filepath.Join(t.workingDir, searchPath)
	}

	// Get file types filter
	fileTypes := defaultFileTypes
	if typesArg, ok := args["file_types"]; ok {
		switch v := typesArg.(type) {
		case []interface{}:
			fileTypes = make([]string, len(v))
			for i, ft := range v {
				if s, ok := ft.(string); ok {
					fileTypes[i] = s
				}
			}
		case string:
			fileTypes = strings.Split(v, ",")
		}
	}

	// Build extension map for fast lookup
	extMap := make(map[string]bool)
	for _, ext := range fileTypes {
		ext = strings.TrimSpace(ext)
		if !strings.HasPrefix(ext, ".") {
			ext = "." + ext
		}
		extMap[ext] = true
	}

	// Search results
	type match struct {
		File    string
		Line    int
		Content string
	}
	var matches []match
	maxMatches := 100
	maxFiles := 500
	filesSearched := 0

	err = filepath.Walk(searchPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip files we can't access
		}

		// Check context cancellation
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Skip directories
		if info.IsDir() {
			// Skip hidden directories and common non-code directories
			name := info.Name()
			if strings.HasPrefix(name, ".") || name == "node_modules" || name == "vendor" || name == "__pycache__" || name == "venv" {
				return filepath.SkipDir
			}
			return nil
		}

		// Check file extension
		ext := filepath.Ext(path)
		if !extMap[ext] {
			return nil
		}

		filesSearched++
		if filesSearched > maxFiles {
			return filepath.SkipAll
		}

		// Read and search file
		file, err := os.Open(path)
		if err != nil {
			return nil // Skip files we can't open
		}
		defer file.Close()

		relPath, _ := filepath.Rel(searchPath, path)
		scanner := bufio.NewScanner(file)
		lineNum := 0

		for scanner.Scan() {
			lineNum++
			line := scanner.Text()

			if re.MatchString(line) {
				if len(matches) >= maxMatches {
					return filepath.SkipAll
				}
				matches = append(matches, match{
					File:    relPath,
					Line:    lineNum,
					Content: truncateLine(line, 120),
				})
			}
		}

		return nil
	})

	if err != nil && err != filepath.SkipAll {
		return "", fmt.Errorf("error searching files: %w", err)
	}

	if len(matches) == 0 {
		return fmt.Sprintf("No matches found for pattern: %s", pattern), nil
	}

	// Format results
	var result strings.Builder
	result.WriteString(fmt.Sprintf("Found %d matches for pattern: %s\n\n", len(matches), pattern))

	currentFile := ""
	for _, m := range matches {
		if m.File != currentFile {
			currentFile = m.File
			result.WriteString(fmt.Sprintf("\n=== %s ===\n", m.File))
		}
		result.WriteString(fmt.Sprintf("%4d: %s\n", m.Line, m.Content))
	}

	if len(matches) >= maxMatches {
		result.WriteString(fmt.Sprintf("\n... (limited to %d matches)", maxMatches))
	}

	return result.String(), nil
}

func truncateLine(line string, maxLen int) string {
	if len(line) <= maxLen {
		return line
	}
	return line[:maxLen-3] + "..."
}
