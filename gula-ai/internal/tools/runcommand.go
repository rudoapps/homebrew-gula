package tools

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// RunCommandTool executes shell commands
type RunCommandTool struct {
	workingDir string
}

func (t *RunCommandTool) Name() string {
	return "run_command"
}

func (t *RunCommandTool) Description() string {
	return "Execute a shell command"
}

func (t *RunCommandTool) NeedsApproval() bool {
	return true // Always requires user approval
}

func (t *RunCommandTool) Execute(ctx context.Context, args map[string]interface{}) (string, error) {
	// Get command argument
	commandArg, ok := args["command"]
	if !ok {
		return "", fmt.Errorf("missing required argument: command")
	}
	command, ok := commandArg.(string)
	if !ok {
		return "", fmt.Errorf("command must be a string")
	}

	// Get timeout argument (default 60 seconds)
	timeout := 60 * time.Second
	if timeoutArg, ok := args["timeout"]; ok {
		if t, ok := timeoutArg.(float64); ok {
			timeout = time.Duration(t) * time.Second
		}
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Execute command
	cmd := exec.CommandContext(ctx, "sh", "-c", command)
	cmd.Dir = t.workingDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	// Build result
	var result strings.Builder

	if stdout.Len() > 0 {
		result.WriteString("=== STDOUT ===\n")
		output := stdout.String()
		if len(output) > 10000 {
			output = output[:10000] + "\n... (truncated)"
		}
		result.WriteString(output)
	}

	if stderr.Len() > 0 {
		if result.Len() > 0 {
			result.WriteString("\n\n")
		}
		result.WriteString("=== STDERR ===\n")
		errOutput := stderr.String()
		if len(errOutput) > 5000 {
			errOutput = errOutput[:5000] + "\n... (truncated)"
		}
		result.WriteString(errOutput)
	}

	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return result.String(), fmt.Errorf("command timed out after %v", timeout)
		}
		if result.Len() > 0 {
			result.WriteString("\n\n")
		}
		result.WriteString(fmt.Sprintf("=== ERROR ===\n%v", err))
	}

	if result.Len() == 0 {
		return "(no output)", nil
	}

	return result.String(), nil
}

// FormatForApproval formats the tool execution for user approval
func (t *RunCommandTool) FormatForApproval(args map[string]interface{}) string {
	command, _ := args["command"].(string)
	timeout := 60.0
	if t, ok := args["timeout"].(float64); ok {
		timeout = t
	}

	return fmt.Sprintf("Execute command:\n\n  $ %s\n\nTimeout: %.0f seconds\nWorking directory: %s",
		command, timeout, t.workingDir)
}
