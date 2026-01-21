package tools

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// GitInfoTool provides git repository information
type GitInfoTool struct {
	workingDir string
}

func (t *GitInfoTool) Name() string {
	return "git_info"
}

func (t *GitInfoTool) Description() string {
	return "Get git repository information (status, log, diff, branch)"
}

func (t *GitInfoTool) NeedsApproval() bool {
	return false // Read-only git operations don't need approval
}

func (t *GitInfoTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get action argument
	actionArg, ok := args["action"]
	if !ok {
		return "", fmt.Errorf("missing required argument: action")
	}
	action, ok := actionArg.(string)
	if !ok {
		return "", fmt.Errorf("action must be a string")
	}

	// Execute based on action
	switch action {
	case "status":
		return t.gitStatus(ctx)
	case "log":
		count := 10
		if c, ok := args["count"].(float64); ok {
			count = int(c)
		}
		return t.gitLog(ctx, count)
	case "diff":
		file := ""
		if f, ok := args["file"].(string); ok {
			file = f
		}
		return t.gitDiff(ctx, file)
	case "branch":
		return t.gitBranch(ctx)
	default:
		return "", fmt.Errorf("unknown action: %s (valid: status, log, diff, branch)", action)
	}
}

func (t *GitInfoTool) runGit(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = t.workingDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("git error: %s", strings.TrimSpace(stderr.String()))
		}
		return "", fmt.Errorf("git error: %w", err)
	}

	return stdout.String(), nil
}

func (t *GitInfoTool) gitStatus(ctx context.Context) (string, error) {
	output, err := t.runGit(ctx, "status", "--short", "--branch")
	if err != nil {
		return "", err
	}

	if strings.TrimSpace(output) == "" {
		return "(no changes)", nil
	}

	return output, nil
}

func (t *GitInfoTool) gitLog(ctx context.Context, count int) (string, error) {
	if count < 1 {
		count = 1
	}
	if count > 50 {
		count = 50
	}

	output, err := t.runGit(ctx, "log",
		fmt.Sprintf("--max-count=%d", count),
		"--pretty=format:%h %s (%ar) <%an>",
	)
	if err != nil {
		return "", err
	}

	if strings.TrimSpace(output) == "" {
		return "(no commits)", nil
	}

	return output, nil
}

func (t *GitInfoTool) gitDiff(ctx context.Context, file string) (string, error) {
	var output string
	var err error

	if file != "" {
		output, err = t.runGit(ctx, "diff", "--", file)
	} else {
		output, err = t.runGit(ctx, "diff")
	}

	if err != nil {
		return "", err
	}

	if strings.TrimSpace(output) == "" {
		return "(no changes)", nil
	}

	// Truncate if too long
	if len(output) > 10000 {
		output = output[:10000] + "\n... (truncated)"
	}

	return output, nil
}

func (t *GitInfoTool) gitBranch(ctx context.Context) (string, error) {
	// Get current branch
	current, err := t.runGit(ctx, "branch", "--show-current")
	if err != nil {
		return "", err
	}
	current = strings.TrimSpace(current)

	// Get all branches
	all, err := t.runGit(ctx, "branch", "-a", "--format=%(refname:short)")
	if err != nil {
		return "", err
	}

	var result strings.Builder
	result.WriteString(fmt.Sprintf("Current branch: %s\n\nAll branches:\n", current))

	branches := strings.Split(strings.TrimSpace(all), "\n")
	for _, branch := range branches {
		if branch == current {
			result.WriteString(fmt.Sprintf("* %s\n", branch))
		} else {
			result.WriteString(fmt.Sprintf("  %s\n", branch))
		}
	}

	return result.String(), nil
}
