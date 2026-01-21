package ui

import (
	"context"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/fer/gula-ai/internal/api"
	"github.com/fer/gula-ai/internal/app"
)

// AppState represents the current state of the application
type AppState int

const (
	StateIdle AppState = iota
	StateConnecting
	StateStreaming
	StateError
)

// Message represents a chat message
type Message struct {
	Role    string // "user", "assistant", "system", "error", "tool"
	Content string
	Model   string
}

// Model is the main application model
type Model struct {
	// Configuration
	Config    *app.Config
	Styles    *Styles
	Keys      KeyMap
	APIClient *api.Client

	// UI State
	Width    int
	Height   int
	AppState AppState
	ShowHelp bool

	// Components
	Input    textarea.Model
	ChatView viewport.Model
	Spinner  spinner.Model

	// Data
	Messages       []Message
	ConversationID int
	CurrentModel   string
	TotalTokens    int
	TotalCost      float64

	// Streaming state
	StreamingContent string

	// Cancel context for API calls
	cancelFunc context.CancelFunc
}

// NewModel creates a new Model with default values
func NewModel(cfg *app.Config) Model {
	// Initialize textarea for input
	ta := textarea.New()
	ta.Placeholder = "Escribe tu mensaje... (Enter para enviar, Ctrl+C para salir)"
	ta.Focus()
	ta.Prompt = "› "
	ta.CharLimit = 10000
	ta.SetWidth(80)
	ta.SetHeight(3)
	ta.ShowLineNumbers = false
	ta.KeyMap.InsertNewline.SetEnabled(false)

	// Initialize spinner
	sp := spinner.New()
	sp.Spinner = spinner.Dot

	// Initialize viewport
	chatVP := viewport.New(80, 20)

	// Create API client
	client := api.NewClient(cfg.APIURL, cfg.AccessToken)

	return Model{
		Config:         cfg,
		Styles:         DefaultStyles(),
		Keys:           DefaultKeyMap(),
		APIClient:      client,
		AppState:       StateIdle,
		ShowHelp:       false,
		Input:          ta,
		ChatView:       chatVP,
		Spinner:        sp,
		Messages:       []Message{},
		CurrentModel:   cfg.DefaultModel,
	}
}

// Init implements tea.Model
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		textarea.Blink,
		m.Spinner.Tick,
	)
}

// AddMessage adds a message and updates the chat view
func (m *Model) AddMessage(role, content string) {
	m.Messages = append(m.Messages, Message{
		Role:    role,
		Content: content,
		Model:   m.CurrentModel,
	})
	m.updateChatView()
}

// updateChatView updates the viewport content
func (m *Model) updateChatView() {
	var sb strings.Builder

	for _, msg := range m.Messages {
		switch msg.Role {
		case "user":
			sb.WriteString(m.Styles.UserPrefix.Render("› "))
			sb.WriteString(m.Styles.UserMessage.Render(msg.Content))
			sb.WriteString("\n\n")
		case "assistant":
			sb.WriteString(m.Styles.AgentPrefix.Render("Agent"))
			if msg.Model != "" {
				sb.WriteString(m.Styles.Dim.Render(" (" + msg.Model + ")"))
			}
			sb.WriteString("\n")
			sb.WriteString(m.Styles.AgentMessage.Render(msg.Content))
			sb.WriteString("\n\n")
		case "system":
			sb.WriteString(m.Styles.SystemMessage.Render(msg.Content))
			sb.WriteString("\n\n")
		case "error":
			sb.WriteString(m.Styles.ErrorMessage.Render("Error: " + msg.Content))
			sb.WriteString("\n\n")
		case "tool":
			sb.WriteString(m.Styles.ToolName.Render("  ⚡ " + msg.Content))
			sb.WriteString("\n")
		}
	}

	// Add streaming content
	if m.StreamingContent != "" {
		sb.WriteString(m.Styles.AgentPrefix.Render("Agent"))
		sb.WriteString("\n")
		sb.WriteString(m.Styles.AgentMessage.Render(m.StreamingContent))
	}

	m.ChatView.SetContent(sb.String())
	m.ChatView.GotoBottom()
}

// updateLayout updates component sizes based on terminal dimensions
func (m *Model) updateLayout() {
	inputHeight := 5
	statusHeight := 1
	chatHeight := m.Height - inputHeight - statusHeight - 2

	m.Input.SetWidth(m.Width - 4)
	m.ChatView.Width = m.Width - 2
	m.ChatView.Height = chatHeight
}
