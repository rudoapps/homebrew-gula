package context

import (
	"os"
	"path/filepath"
)

// ProjectType represents the type of project
type ProjectType string

const (
	ProjectTypeGo         ProjectType = "go"
	ProjectTypePython     ProjectType = "python"
	ProjectTypeNode       ProjectType = "node"
	ProjectTypeRust       ProjectType = "rust"
	ProjectTypeJava       ProjectType = "java"
	ProjectTypeRuby       ProjectType = "ruby"
	ProjectTypeUnknown    ProjectType = "unknown"
)

// ProjectInfo contains information about the detected project
type ProjectInfo struct {
	Type        ProjectType
	Name        string
	RootDir     string
	HasGit      bool
	MainFile    string
	ConfigFiles []string
}

// DetectProject detects the type of project in the given directory
func DetectProject(dir string) (*ProjectInfo, error) {
	info := &ProjectInfo{
		Type:    ProjectTypeUnknown,
		RootDir: dir,
	}

	// Check for git
	if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
		info.HasGit = true
	}

	// Detect project type based on configuration files
	detectors := []struct {
		file    string
		ptype   ProjectType
		configs []string
	}{
		{"go.mod", ProjectTypeGo, []string{"go.mod", "go.sum"}},
		{"Cargo.toml", ProjectTypeRust, []string{"Cargo.toml", "Cargo.lock"}},
		{"package.json", ProjectTypeNode, []string{"package.json", "package-lock.json", "yarn.lock"}},
		{"pyproject.toml", ProjectTypePython, []string{"pyproject.toml", "setup.py", "requirements.txt"}},
		{"requirements.txt", ProjectTypePython, []string{"requirements.txt", "setup.py"}},
		{"pom.xml", ProjectTypeJava, []string{"pom.xml"}},
		{"build.gradle", ProjectTypeJava, []string{"build.gradle", "build.gradle.kts"}},
		{"Gemfile", ProjectTypeRuby, []string{"Gemfile", "Gemfile.lock"}},
	}

	for _, d := range detectors {
		if _, err := os.Stat(filepath.Join(dir, d.file)); err == nil {
			info.Type = d.ptype
			for _, cfg := range d.configs {
				if _, err := os.Stat(filepath.Join(dir, cfg)); err == nil {
					info.ConfigFiles = append(info.ConfigFiles, cfg)
				}
			}
			break
		}
	}

	// Try to get project name
	info.Name = filepath.Base(dir)

	// Find main file based on project type
	switch info.Type {
	case ProjectTypeGo:
		if _, err := os.Stat(filepath.Join(dir, "main.go")); err == nil {
			info.MainFile = "main.go"
		}
	case ProjectTypePython:
		candidates := []string{"main.py", "app.py", "__main__.py"}
		for _, c := range candidates {
			if _, err := os.Stat(filepath.Join(dir, c)); err == nil {
				info.MainFile = c
				break
			}
		}
	case ProjectTypeNode:
		// Check package.json for main field
		info.MainFile = "index.js"
	case ProjectTypeRust:
		if _, err := os.Stat(filepath.Join(dir, "src", "main.rs")); err == nil {
			info.MainFile = "src/main.rs"
		}
	}

	return info, nil
}

// GetProjectSummary returns a brief summary of the project
func (p *ProjectInfo) GetProjectSummary() string {
	summary := p.Name + " (" + string(p.Type) + " project)"
	if p.HasGit {
		summary += " [git]"
	}
	return summary
}
