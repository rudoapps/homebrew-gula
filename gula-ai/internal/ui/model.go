package ui

import (
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/fer/gula-ai/internal/app"
)

// FocusedPanel represents which panel is currently focused
type FocusedPanel int

const (
	FocusInput FocusedPanel = iota
	FocusChat
	FocusTools
)

// AppState represents the current state of the application
type AppState int

const (
	StateIdle AppState = iota
	StateThinking
	StateStreaming
	StateWaitingApproval
	StateError
)

// Message represents a chat message
type Message struct {
	Role    string // "user", "assistant", "system", "error"
	Content string
	Model   string // For assistant messages
}

// ToolExecution represents a tool being executed
type ToolExecution struct {
	Name       string
	Args       map[string]interface{}
	Status     string // "pending", "running", "complete", "error"
	Result     string
	Error      string
	NeedsApproval bool
}

// SessionStats holds session statistics
type SessionStats struct {
	ConversationID string
	TotalTokens    int
	InputTokens    int
	OutputTokens   int
	TotalCost      float64
}

// Model is the main application model
type Model struct {
	// Configuration
	Config *app.Config
	Styles *Styles
	Keys   KeyMap

	// UI State
	Width         int
	Height        int
	FocusedPanel  FocusedPanel
	ShowToolsPanel bool
	ShowHelp      bool
	AppState      AppState

	// Components
	Input    textarea.Model
	ChatView viewport.Model
	ToolView viewport.Model
	Spinner  spinner.Model

	// Data
	Messages     []Message
	Tools        []ToolExecution
	Stats        SessionStats
	CurrentModel string

	// Streaming state
	StreamingContent string
	IsStreaming      bool

	// Error state
	LastError string

	// Dialog state
	DialogActive  bool
	DialogTitle   string
	DialogContent string
	DialogTool    *ToolExecution
}

// NewModel creates a new Model with default values
func NewModel(cfg *app.Config) Model {
	// Initialize textarea for input
	ta := textarea.New()
	ta.Placeholder = "Type your message..."
	ta.Focus()
	ta.Prompt = "› "
	ta.CharLimit = 10000
	ta.SetWidth(80)
	ta.SetHeight(1)
	ta.ShowLineNumbers = false
	ta.KeyMap.InsertNewline.SetEnabled(false) // We'll handle newlines ourselves

	// Initialize spinner
	sp := spinner.New()
	sp.Spinner = spinner.Dot

	// Initialize viewports
	chatVP := viewport.New(80, 20)
	toolVP := viewport.New(25, 20)

	return Model{
		Config:         cfg,
		Styles:         DefaultStyles(),
		Keys:           DefaultKeyMap(),
		FocusedPanel:   FocusInput,
		ShowToolsPanel: true,
		ShowHelp:       false,
		AppState:       StateIdle,
		Input:          ta,
		ChatView:       chatVP,
		ToolView:       toolVP,
		Spinner:        sp,
		Messages:       []Message{},
		Tools:          []ToolExecution{},
		Stats:          SessionStats{},
		CurrentModel:   cfg.DefaultModel,
		IsStreaming:    false,
	}
}

// Init implements tea.Model
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		textarea.Blink,
		m.Spinner.Tick,
	)
}
