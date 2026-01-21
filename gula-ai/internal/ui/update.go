package ui

import (
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
)

// Custom messages
type (
	// SSE event messages
	SSEStartedMsg struct {
		ConversationID string
		Model          string
	}
	SSEThinkingMsg struct{}
	SSETextMsg struct {
		Content string
	}
	SSEToolRequestsMsg struct {
		Tools []ToolExecution
	}
	SSERAGSearchMsg struct {
		Query string
	}
	SSERAGContextMsg struct {
		Chunks []string
	}
	SSECompleteMsg struct {
		TotalTokens  int
		InputTokens  int
		OutputTokens int
		TotalCost    float64
	}
	SSEErrorMsg struct {
		Error string
	}
	SSERateLimitedMsg struct {
		RetryAfter int
	}
	SSECostWarningMsg struct {
		Message string
	}

	// Tool execution messages
	ToolResultMsg struct {
		Index  int
		Result string
		Error  string
	}
	ToolApprovalMsg struct {
		Index    int
		Approved bool
	}

	// Error message
	ErrMsg struct {
		Error error
	}
)

// Update implements tea.Model
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyMsg(msg)

	case tea.WindowSizeMsg:
		return m.handleWindowSize(msg)

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.Spinner, cmd = m.Spinner.Update(msg)
		return m, cmd

	case SSEStartedMsg:
		m.Stats.ConversationID = msg.ConversationID
		m.CurrentModel = msg.Model
		m.AppState = StateThinking
		return m, nil

	case SSEThinkingMsg:
		m.AppState = StateThinking
		return m, nil

	case SSETextMsg:
		m.AppState = StateStreaming
		m.IsStreaming = true
		m.StreamingContent += msg.Content
		m.updateChatView()
		return m, nil

	case SSEToolRequestsMsg:
		m.Tools = append(m.Tools, msg.Tools...)
		m.updateToolView()
		// Check if any tool needs approval
		for i, tool := range msg.Tools {
			if tool.NeedsApproval {
				m.DialogActive = true
				m.DialogTitle = "Approve Tool Execution"
				m.DialogContent = formatToolForApproval(tool)
				m.DialogTool = &m.Tools[len(m.Tools)-len(msg.Tools)+i]
				m.AppState = StateWaitingApproval
				break
			}
		}
		return m, nil

	case SSERAGSearchMsg:
		// Add a system message about RAG search
		m.Messages = append(m.Messages, Message{
			Role:    "system",
			Content: "🔍 Searching codebase: " + msg.Query,
		})
		m.updateChatView()
		return m, nil

	case SSECompleteMsg:
		m.AppState = StateIdle
		m.IsStreaming = false
		// Finalize the streaming message
		if m.StreamingContent != "" {
			m.Messages = append(m.Messages, Message{
				Role:    "assistant",
				Content: m.StreamingContent,
				Model:   m.CurrentModel,
			})
			m.StreamingContent = ""
		}
		m.Stats.TotalTokens = msg.TotalTokens
		m.Stats.InputTokens = msg.InputTokens
		m.Stats.OutputTokens = msg.OutputTokens
		m.Stats.TotalCost = msg.TotalCost
		m.updateChatView()
		return m, nil

	case SSEErrorMsg:
		m.AppState = StateError
		m.LastError = msg.Error
		m.IsStreaming = false
		m.Messages = append(m.Messages, Message{
			Role:    "error",
			Content: msg.Error,
		})
		m.updateChatView()
		return m, nil

	case ToolResultMsg:
		if msg.Index < len(m.Tools) {
			if msg.Error != "" {
				m.Tools[msg.Index].Status = "error"
				m.Tools[msg.Index].Error = msg.Error
			} else {
				m.Tools[msg.Index].Status = "complete"
				m.Tools[msg.Index].Result = msg.Result
			}
			m.updateToolView()
		}
		return m, nil

	case ToolApprovalMsg:
		if m.DialogTool != nil {
			if msg.Approved {
				m.DialogTool.Status = "running"
				// TODO: Execute the tool
			} else {
				m.DialogTool.Status = "error"
				m.DialogTool.Error = "Rejected by user"
			}
			m.DialogActive = false
			m.DialogTool = nil
			m.AppState = StateIdle
			m.updateToolView()
		}
		return m, nil

	case ErrMsg:
		m.AppState = StateError
		m.LastError = msg.Error.Error()
		return m, nil
	}

	// Update sub-components based on focus
	switch m.FocusedPanel {
	case FocusInput:
		var cmd tea.Cmd
		m.Input, cmd = m.Input.Update(msg)
		cmds = append(cmds, cmd)
	case FocusChat:
		var cmd tea.Cmd
		m.ChatView, cmd = m.ChatView.Update(msg)
		cmds = append(cmds, cmd)
	case FocusTools:
		var cmd tea.Cmd
		m.ToolView, cmd = m.ToolView.Update(msg)
		cmds = append(cmds, cmd)
	}

	return m, tea.Batch(cmds...)
}

func (m Model) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Handle dialog keys first
	if m.DialogActive {
		switch msg.String() {
		case "y", "Y", "enter":
			return m, func() tea.Msg {
				return ToolApprovalMsg{Approved: true}
			}
		case "n", "N", "esc":
			return m, func() tea.Msg {
				return ToolApprovalMsg{Approved: false}
			}
		}
		return m, nil
	}

	// Global keys
	switch {
	case key.Matches(msg, m.Keys.Quit):
		return m, tea.Quit

	case key.Matches(msg, m.Keys.Help):
		m.ShowHelp = !m.ShowHelp
		return m, nil

	case key.Matches(msg, m.Keys.Tab):
		m.cycleFocus()
		return m, nil

	case key.Matches(msg, m.Keys.ToggleTools):
		m.ShowToolsPanel = !m.ShowToolsPanel
		m.updateLayout()
		return m, nil

	case key.Matches(msg, m.Keys.NewConversation):
		m.newConversation()
		return m, nil

	case key.Matches(msg, m.Keys.Cancel):
		if m.IsStreaming {
			// TODO: Cancel streaming
			m.AppState = StateIdle
			m.IsStreaming = false
		} else if m.FocusedPanel != FocusInput {
			m.FocusedPanel = FocusInput
			m.Input.Focus()
		}
		return m, nil
	}

	// Input-specific keys
	if m.FocusedPanel == FocusInput {
		switch {
		case key.Matches(msg, m.Keys.Send):
			return m.sendMessage()
		case key.Matches(msg, m.Keys.NewLine):
			m.Input.InsertString("\n")
			return m, nil
		}

		// Pass to textarea
		var cmd tea.Cmd
		m.Input, cmd = m.Input.Update(msg)
		return m, cmd
	}

	// Chat panel navigation
	if m.FocusedPanel == FocusChat {
		switch {
		case key.Matches(msg, m.Keys.Up):
			m.ChatView.LineUp(1)
		case key.Matches(msg, m.Keys.Down):
			m.ChatView.LineDown(1)
		case key.Matches(msg, m.Keys.PageUp):
			m.ChatView.HalfViewUp()
		case key.Matches(msg, m.Keys.PageDown):
			m.ChatView.HalfViewDown()
		case key.Matches(msg, m.Keys.Home):
			m.ChatView.GotoTop()
		case key.Matches(msg, m.Keys.End):
			m.ChatView.GotoBottom()
		}
		return m, nil
	}

	// Tools panel navigation
	if m.FocusedPanel == FocusTools {
		switch {
		case key.Matches(msg, m.Keys.Up):
			m.ToolView.LineUp(1)
		case key.Matches(msg, m.Keys.Down):
			m.ToolView.LineDown(1)
		}
		return m, nil
	}

	return m, nil
}

func (m Model) handleWindowSize(msg tea.WindowSizeMsg) (tea.Model, tea.Cmd) {
	m.Width = msg.Width
	m.Height = msg.Height
	m.updateLayout()
	return m, nil
}

func (m *Model) updateLayout() {
	// Calculate panel sizes
	inputHeight := 3
	statusHeight := 1
	chatHeight := m.Height - inputHeight - statusHeight - 4 // borders

	if m.ShowToolsPanel {
		toolsWidth := 25
		chatWidth := m.Width - toolsWidth - 3 // borders and padding

		m.Input.SetWidth(m.Width - 4)
		m.ChatView.Width = chatWidth
		m.ChatView.Height = chatHeight
		m.ToolView.Width = toolsWidth
		m.ToolView.Height = chatHeight
	} else {
		m.Input.SetWidth(m.Width - 4)
		m.ChatView.Width = m.Width - 4
		m.ChatView.Height = chatHeight
	}
}

func (m *Model) cycleFocus() {
	switch m.FocusedPanel {
	case FocusInput:
		m.FocusedPanel = FocusChat
		m.Input.Blur()
	case FocusChat:
		if m.ShowToolsPanel {
			m.FocusedPanel = FocusTools
		} else {
			m.FocusedPanel = FocusInput
			m.Input.Focus()
		}
	case FocusTools:
		m.FocusedPanel = FocusInput
		m.Input.Focus()
	}
}

func (m *Model) newConversation() {
	m.Messages = []Message{}
	m.Tools = []ToolExecution{}
	m.Stats = SessionStats{}
	m.StreamingContent = ""
	m.IsStreaming = false
	m.AppState = StateIdle
	m.Input.Reset()
	m.updateChatView()
	m.updateToolView()
}

func (m Model) sendMessage() (tea.Model, tea.Cmd) {
	content := m.Input.Value()
	if content == "" || m.AppState == StateStreaming || m.AppState == StateThinking {
		return m, nil
	}

	// Add user message
	m.Messages = append(m.Messages, Message{
		Role:    "user",
		Content: content,
	})
	m.Input.Reset()
	m.AppState = StateThinking
	m.updateChatView()

	// TODO: Send to API
	// For now, just return a mock response
	return m, nil
}

func (m *Model) updateChatView() {
	content := m.renderMessages()
	m.ChatView.SetContent(content)
	m.ChatView.GotoBottom()
}

func (m *Model) updateToolView() {
	content := m.renderTools()
	m.ToolView.SetContent(content)
}

func (m Model) renderMessages() string {
	var result string
	for _, msg := range m.Messages {
		switch msg.Role {
		case "user":
			result += m.Styles.UserMessage.Render("› " + msg.Content) + "\n\n"
		case "assistant":
			result += m.Styles.AgentMessage.Render(msg.Content) + "\n\n"
		case "system":
			result += m.Styles.SystemMessage.Render(msg.Content) + "\n\n"
		case "error":
			result += m.Styles.ErrorMessage.Render("Error: " + msg.Content) + "\n\n"
		}
	}
	// Add streaming content if any
	if m.StreamingContent != "" {
		result += m.Styles.AgentMessage.Render(m.StreamingContent)
	}
	return result
}

func (m Model) renderTools() string {
	var result string
	for _, tool := range m.Tools {
		var statusIcon string
		switch tool.Status {
		case "pending":
			statusIcon = "○"
		case "running":
			statusIcon = "◐"
		case "complete":
			statusIcon = "✓"
		case "error":
			statusIcon = "✗"
		}
		result += m.Styles.ToolItem.Render(statusIcon + " " + tool.Name) + "\n"
	}
	if len(m.Tools) == 0 {
		result = m.Styles.ToolItem.Render("No tools executed")
	}
	return result
}

func formatToolForApproval(tool ToolExecution) string {
	return "Tool: " + tool.Name + "\n\nApprove? (y/n)"
}
