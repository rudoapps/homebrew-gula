package tools

import (
	"context"
	"fmt"
)

// Tool represents a local tool that can be executed
type Tool interface {
	Name() string
	Description() string
	NeedsApproval() bool
	Execute(ctx context.Context, args map[string]interface{}) (string, error)
}

// Executor manages and executes local tools
type Executor struct {
	tools      map[string]Tool
	workingDir string
}

// NewExecutor creates a new tool executor
func NewExecutor(workingDir string) *Executor {
	e := &Executor{
		tools:      make(map[string]Tool),
		workingDir: workingDir,
	}

	// Register all tools
	e.Register(&ReadFileTool{workingDir: workingDir})
	e.Register(&WriteFileTool{workingDir: workingDir})
	e.Register(&ListFilesTool{workingDir: workingDir})
	e.Register(&SearchCodeTool{workingDir: workingDir})
	e.Register(&RunCommandTool{workingDir: workingDir})
	e.Register(&GitInfoTool{workingDir: workingDir})

	return e
}

// Register registers a tool
func (e *Executor) Register(tool Tool) {
	e.tools[tool.Name()] = tool
}

// Get returns a tool by name
func (e *Executor) Get(name string) (Tool, bool) {
	tool, ok := e.tools[name]
	return tool, ok
}

// List returns all registered tools
func (e *Executor) List() []Tool {
	result := make([]Tool, 0, len(e.tools))
	for _, tool := range e.tools {
		result = append(result, tool)
	}
	return result
}

// Execute executes a tool by name
func (e *Executor) Execute(ctx context.Context, name string, args map[string]interface{}) (string, error) {
	tool, ok := e.tools[name]
	if !ok {
		return "", fmt.Errorf("unknown tool: %s", name)
	}

	return tool.Execute(ctx, args)
}

// NeedsApproval returns true if the tool requires user approval
func (e *Executor) NeedsApproval(name string) bool {
	tool, ok := e.tools[name]
	if !ok {
		return true // Unknown tools need approval
	}
	return tool.NeedsApproval()
}

// ToolsRequiringApproval returns the list of tool names that need approval
func ToolsRequiringApproval() []string {
	return []string{"write_file", "run_command"}
}
