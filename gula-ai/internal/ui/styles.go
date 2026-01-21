package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// Colors - minimal dark theme like Claude Code
var (
	ColorText      = lipgloss.Color("#E5E5E5") // Light gray text
	ColorTextDim   = lipgloss.Color("#737373") // Dimmed text
	ColorAccent    = lipgloss.Color("#F5A623") // Amber for agent
	ColorUser      = lipgloss.Color("#60A5FA") // Blue for user
	ColorSuccess   = lipgloss.Color("#4ADE80") // Green
	ColorError     = lipgloss.Color("#F87171") // Red
)

// Styles defines all the styles for the UI
type Styles struct {
	// Text styles
	Normal  lipgloss.Style
	Dim     lipgloss.Style
	Bold    lipgloss.Style

	// Message styles
	UserPrefix    lipgloss.Style
	AgentPrefix   lipgloss.Style
	UserMessage   lipgloss.Style
	AgentMessage  lipgloss.Style
	SystemMessage lipgloss.Style
	ErrorMessage  lipgloss.Style

	// Tool styles
	ToolName    lipgloss.Style
	ToolSuccess lipgloss.Style
	ToolError   lipgloss.Style

	// Input
	InputPrompt lipgloss.Style

	// Status
	StatusText lipgloss.Style
	Spinner    lipgloss.Style
}

// DefaultStyles returns minimal styles
func DefaultStyles() *Styles {
	return &Styles{
		Normal: lipgloss.NewStyle().Foreground(ColorText),
		Dim:    lipgloss.NewStyle().Foreground(ColorTextDim),
		Bold:   lipgloss.NewStyle().Bold(true).Foreground(ColorText),

		UserPrefix:    lipgloss.NewStyle().Foreground(ColorUser).Bold(true),
		AgentPrefix:   lipgloss.NewStyle().Foreground(ColorAccent).Bold(true),
		UserMessage:   lipgloss.NewStyle().Foreground(ColorText),
		AgentMessage:  lipgloss.NewStyle().Foreground(ColorText),
		SystemMessage: lipgloss.NewStyle().Foreground(ColorTextDim).Italic(true),
		ErrorMessage:  lipgloss.NewStyle().Foreground(ColorError),

		ToolName:    lipgloss.NewStyle().Foreground(ColorAccent),
		ToolSuccess: lipgloss.NewStyle().Foreground(ColorSuccess),
		ToolError:   lipgloss.NewStyle().Foreground(ColorError),

		InputPrompt: lipgloss.NewStyle().Foreground(ColorUser).Bold(true),

		StatusText: lipgloss.NewStyle().Foreground(ColorTextDim),
		Spinner:    lipgloss.NewStyle().Foreground(ColorAccent),
	}
}
