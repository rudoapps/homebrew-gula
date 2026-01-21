package context

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// TreeOptions configures tree generation
type TreeOptions struct {
	MaxDepth     int
	MaxFiles     int
	IncludeHidden bool
	IgnoreDirs   []string
}

// DefaultTreeOptions returns sensible defaults
func DefaultTreeOptions() TreeOptions {
	return TreeOptions{
		MaxDepth:     4,
		MaxFiles:     200,
		IncludeHidden: false,
		IgnoreDirs: []string{
			".git", "node_modules", "__pycache__", ".venv", "venv",
			"vendor", "target", "build", "dist", ".cache", ".idea",
			".vscode", "coverage", ".pytest_cache", ".mypy_cache",
		},
	}
}

// GenerateTree generates a tree representation of the directory
func GenerateTree(root string, opts TreeOptions) (string, error) {
	var result strings.Builder
	fileCount := 0

	// Build ignore map
	ignoreMap := make(map[string]bool)
	for _, dir := range opts.IgnoreDirs {
		ignoreMap[dir] = true
	}

	err := generateTreeRecursive(&result, root, "", 0, opts, ignoreMap, &fileCount)
	if err != nil {
		return "", err
	}

	if fileCount >= opts.MaxFiles {
		result.WriteString("\n... (tree truncated)\n")
	}

	return result.String(), nil
}

func generateTreeRecursive(result *strings.Builder, path, prefix string, depth int, opts TreeOptions, ignoreMap map[string]bool, fileCount *int) error {
	if depth > opts.MaxDepth || *fileCount >= opts.MaxFiles {
		return nil
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return err
	}

	// Filter and sort entries
	var filtered []os.DirEntry
	for _, entry := range entries {
		name := entry.Name()

		// Skip hidden files/dirs unless explicitly included
		if !opts.IncludeHidden && strings.HasPrefix(name, ".") {
			continue
		}

		// Skip ignored directories
		if entry.IsDir() && ignoreMap[name] {
			continue
		}

		filtered = append(filtered, entry)
	}

	// Sort: directories first, then files
	sort.Slice(filtered, func(i, j int) bool {
		iDir := filtered[i].IsDir()
		jDir := filtered[j].IsDir()
		if iDir != jDir {
			return iDir
		}
		return filtered[i].Name() < filtered[j].Name()
	})

	for i, entry := range filtered {
		if *fileCount >= opts.MaxFiles {
			return nil
		}

		isLast := i == len(filtered)-1
		connector := "├── "
		if isLast {
			connector = "└── "
		}

		name := entry.Name()
		if entry.IsDir() {
			name += "/"
		}

		result.WriteString(prefix + connector + name + "\n")
		*fileCount++

		if entry.IsDir() {
			newPrefix := prefix + "│   "
			if isLast {
				newPrefix = prefix + "    "
			}
			err := generateTreeRecursive(result, filepath.Join(path, entry.Name()), newPrefix, depth+1, opts, ignoreMap, fileCount)
			if err != nil {
				// Continue on error, just skip this directory
				continue
			}
		}
	}

	return nil
}

// GenerateCompactTree generates a more compact tree with just top-level structure
func GenerateCompactTree(root string) (string, error) {
	opts := TreeOptions{
		MaxDepth:     2,
		MaxFiles:     50,
		IncludeHidden: false,
		IgnoreDirs:  DefaultTreeOptions().IgnoreDirs,
	}
	return GenerateTree(root, opts)
}
