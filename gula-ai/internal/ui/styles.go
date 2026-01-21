package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// Colors for the dark theme
var (
	// Primary colors
	ColorPrimary    = lipgloss.Color("#7C3AED") // Purple
	ColorSecondary  = lipgloss.Color("#10B981") // Green
	ColorAccent     = lipgloss.Color("#F59E0B") // Amber
	ColorError      = lipgloss.Color("#EF4444") // Red
	ColorWarning    = lipgloss.Color("#F59E0B") // Amber
	ColorSuccess    = lipgloss.Color("#10B981") // Green

	// Background colors
	ColorBg        = lipgloss.Color("#1F2937") // Dark gray
	ColorBgDark    = lipgloss.Color("#111827") // Darker gray
	ColorBgLight   = lipgloss.Color("#374151") // Lighter gray
	ColorBgPanel   = lipgloss.Color("#1F2937") // Panel background

	// Text colors
	ColorText       = lipgloss.Color("#F9FAFB") // White
	ColorTextMuted  = lipgloss.Color("#9CA3AF") // Gray
	ColorTextDim    = lipgloss.Color("#6B7280") // Dimmer gray

	// Border colors
	ColorBorder       = lipgloss.Color("#374151") // Gray border
	ColorBorderActive = lipgloss.Color("#7C3AED") // Purple border when active
)

// Styles defines all the styles for the UI
type Styles struct {
	// App container
	App lipgloss.Style

	// Panels
	ChatPanel       lipgloss.Style
	ChatPanelActive lipgloss.Style
	ToolsPanel      lipgloss.Style
	ToolsPanelActive lipgloss.Style

	// Messages
	UserMessage   lipgloss.Style
	AgentMessage  lipgloss.Style
	SystemMessage lipgloss.Style
	ErrorMessage  lipgloss.Style

	// Status bar
	StatusBar     lipgloss.Style
	StatusModel   lipgloss.Style
	StatusSession lipgloss.Style
	StatusCost    lipgloss.Style
	StatusTokens  lipgloss.Style
	StatusRAG     lipgloss.Style

	// Input
	InputArea        lipgloss.Style
	InputPrompt      lipgloss.Style
	InputText        lipgloss.Style
	InputPlaceholder lipgloss.Style

	// Tools
	ToolItem      lipgloss.Style
	ToolRunning   lipgloss.Style
	ToolComplete  lipgloss.Style
	ToolError     lipgloss.Style
	ToolPending   lipgloss.Style

	// Dialog
	Dialog       lipgloss.Style
	DialogTitle  lipgloss.Style
	DialogButton lipgloss.Style

	// Misc
	Title     lipgloss.Style
	Subtitle  lipgloss.Style
	Spinner   lipgloss.Style
	Help      lipgloss.Style
	Thinking  lipgloss.Style
}

// DefaultStyles returns the default styles for the UI
func DefaultStyles() *Styles {
	return &Styles{
		// App container
		App: lipgloss.NewStyle().
			Background(ColorBgDark),

		// Chat Panel
		ChatPanel: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorder).
			Padding(0, 1),

		ChatPanelActive: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorderActive).
			Padding(0, 1),

		// Tools Panel
		ToolsPanel: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorder).
			Padding(0, 1),

		ToolsPanelActive: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorderActive).
			Padding(0, 1),

		// Messages
		UserMessage: lipgloss.NewStyle().
			Foreground(ColorText).
			PaddingLeft(2).
			MarginBottom(1),

		AgentMessage: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorPrimary).
			Padding(1, 2).
			MarginBottom(1),

		SystemMessage: lipgloss.NewStyle().
			Foreground(ColorTextMuted).
			Italic(true).
			PaddingLeft(2).
			MarginBottom(1),

		ErrorMessage: lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true).
			PaddingLeft(2).
			MarginBottom(1),

		// Status bar
		StatusBar: lipgloss.NewStyle().
			Background(ColorBgLight).
			Padding(0, 1).
			Height(1),

		StatusModel: lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true).
			Padding(0, 1),

		StatusSession: lipgloss.NewStyle().
			Foreground(ColorTextMuted).
			Padding(0, 1),

		StatusCost: lipgloss.NewStyle().
			Foreground(ColorAccent).
			Padding(0, 1),

		StatusTokens: lipgloss.NewStyle().
			Foreground(ColorTextMuted).
			Padding(0, 1),

		StatusRAG: lipgloss.NewStyle().
			Foreground(ColorSecondary).
			Padding(0, 1),

		// Input
		InputArea: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorder).
			Padding(0, 1),

		InputPrompt: lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true),

		InputText: lipgloss.NewStyle().
			Foreground(ColorText),

		InputPlaceholder: lipgloss.NewStyle().
			Foreground(ColorTextDim).
			Italic(true),

		// Tools
		ToolItem: lipgloss.NewStyle().
			Foreground(ColorText).
			PaddingLeft(1),

		ToolRunning: lipgloss.NewStyle().
			Foreground(ColorAccent),

		ToolComplete: lipgloss.NewStyle().
			Foreground(ColorSuccess),

		ToolError: lipgloss.NewStyle().
			Foreground(ColorError),

		ToolPending: lipgloss.NewStyle().
			Foreground(ColorTextMuted),

		// Dialog
		Dialog: lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(ColorPrimary).
			Padding(1, 2).
			Background(ColorBg),

		DialogTitle: lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true).
			MarginBottom(1),

		DialogButton: lipgloss.NewStyle().
			Foreground(ColorText).
			Background(ColorBgLight).
			Padding(0, 2).
			MarginRight(1),

		// Misc
		Title: lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true),

		Subtitle: lipgloss.NewStyle().
			Foreground(ColorTextMuted),

		Spinner: lipgloss.NewStyle().
			Foreground(ColorPrimary),

		Help: lipgloss.NewStyle().
			Foreground(ColorTextDim),

		Thinking: lipgloss.NewStyle().
			Foreground(ColorAccent).
			Italic(true),
	}
}
