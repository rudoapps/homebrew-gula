package ui

import (
	"context"
	"strconv"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/fer/gula-ai/internal/api"
)

// Custom messages for SSE events
type (
	SSEStartedMsg struct {
		ConversationID int
		Model          string
	}
	SSETextMsg struct {
		Content string
	}
	SSECompleteMsg struct {
		TotalTokens int
		TotalCost   float64
	}
	SSEErrorMsg struct {
		Error string
	}
	StreamDoneMsg  struct{}
	StreamEventMsg struct {
		EventType api.EventType
		Data      interface{}
		Err       error
		Channel   chan StreamEventMsg
	}
)

// Update implements tea.Model
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyMsg(msg)

	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		m.updateLayout()
		return m, nil

	case spinner.TickMsg:
		if m.AppState == StateConnecting || m.AppState == StateStreaming {
			var cmd tea.Cmd
			m.Spinner, cmd = m.Spinner.Update(msg)
			return m, cmd
		}
		return m, nil

	case StreamEventMsg:
		return m.handleStreamEvent(msg)

	case SSEStartedMsg:
		m.ConversationID = msg.ConversationID
		m.CurrentModel = msg.Model
		m.AppState = StateStreaming
		return m, nil

	case SSETextMsg:
		m.AppState = StateStreaming
		m.StreamingContent += msg.Content
		m.updateChatView()
		return m, nil

	case SSECompleteMsg:
		m.AppState = StateIdle
		// Finalize the streaming message
		if m.StreamingContent != "" {
			m.Messages = append(m.Messages, Message{
				Role:    "assistant",
				Content: m.StreamingContent,
				Model:   m.CurrentModel,
			})
			m.StreamingContent = ""
		}
		m.TotalTokens = msg.TotalTokens
		m.TotalCost = msg.TotalCost
		m.updateChatView()
		return m, nil

	case SSEErrorMsg:
		m.AppState = StateError
		m.AddMessage("error", msg.Error)
		m.StreamingContent = ""
		return m, nil

	case StreamDoneMsg:
		m.AppState = StateIdle
		return m, nil
	}

	// Update input component
	var cmd tea.Cmd
	m.Input, cmd = m.Input.Update(msg)
	return m, cmd
}

func (m Model) handleStreamEvent(msg StreamEventMsg) (tea.Model, tea.Cmd) {
	if msg.Err != nil {
		m.AppState = StateError
		m.AddMessage("error", msg.Err.Error())
		m.StreamingContent = ""
		return m, nil
	}

	switch msg.EventType {
	case api.EventStarted:
		if started, ok := msg.Data.(*api.StartedEvent); ok {
			convID := 0
			if started.ConversationID != "" {
				if id, err := strconv.Atoi(started.ConversationID); err == nil {
					convID = id
				}
			}
			m.ConversationID = convID
			m.CurrentModel = started.Model
			m.AppState = StateStreaming
		}

	case api.EventText:
		if text, ok := msg.Data.(*api.TextEvent); ok {
			m.AppState = StateStreaming
			m.StreamingContent += text.Content
			m.updateChatView()
		}

	case api.EventComplete:
		if complete, ok := msg.Data.(*api.CompleteEvent); ok {
			m.AppState = StateIdle
			if m.StreamingContent != "" {
				m.Messages = append(m.Messages, Message{
					Role:    "assistant",
					Content: m.StreamingContent,
					Model:   m.CurrentModel,
				})
				m.StreamingContent = ""
			}
			m.TotalTokens = complete.TotalTokens
			m.TotalCost = complete.TotalCost
			m.updateChatView()
		}
		return m, nil // Don't listen for more events

	case api.EventError:
		if errEvent, ok := msg.Data.(*api.ErrorEvent); ok {
			m.AppState = StateError
			m.AddMessage("error", errEvent.Error)
			m.StreamingContent = ""
		}
		return m, nil // Don't listen for more events
	}

	// Continue listening for events
	return m, listenForStreamEvents(msg.Channel)
}

func listenForStreamEvents(ch chan StreamEventMsg) tea.Cmd {
	return func() tea.Msg {
		msg, ok := <-ch
		if !ok {
			return StreamDoneMsg{}
		}
		return msg
	}
}

func (m Model) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global keys
	switch {
	case key.Matches(msg, m.Keys.Quit):
		// Cancel any ongoing request
		if m.cancelFunc != nil {
			m.cancelFunc()
		}
		return m, tea.Quit

	case key.Matches(msg, m.Keys.Help):
		m.ShowHelp = !m.ShowHelp
		return m, nil

	case key.Matches(msg, m.Keys.NewConversation):
		m.Messages = []Message{}
		m.ConversationID = 0
		m.StreamingContent = ""
		m.TotalTokens = 0
		m.TotalCost = 0
		m.AppState = StateIdle
		m.Input.Reset()
		m.updateChatView()
		return m, nil

	case key.Matches(msg, m.Keys.Cancel):
		if m.AppState == StateConnecting || m.AppState == StateStreaming {
			if m.cancelFunc != nil {
				m.cancelFunc()
			}
			m.AppState = StateIdle
			m.AddMessage("system", "Cancelado")
		}
		return m, nil

	case key.Matches(msg, m.Keys.Send):
		return m.sendMessage()
	}

	// Pass to textarea
	var cmd tea.Cmd
	m.Input, cmd = m.Input.Update(msg)
	return m, cmd
}

func (m Model) sendMessage() (tea.Model, tea.Cmd) {
	content := m.Input.Value()
	if content == "" || m.AppState == StateStreaming || m.AppState == StateConnecting {
		return m, nil
	}

	// Add user message
	m.AddMessage("user", content)
	m.Input.Reset()
	m.AppState = StateConnecting
	m.StreamingContent = ""

	// Create cancellable context
	ctx, cancel := context.WithCancel(context.Background())
	m.cancelFunc = cancel

	// Create channel for streaming events
	eventChan := make(chan StreamEventMsg, 100)

	// Start streaming in goroutine
	go m.streamToChannel(ctx, content, eventChan)

	// Return command to listen for first event
	return m, listenForStreamEvents(eventChan)
}

// streamToChannel streams the chat response to a channel
func (m Model) streamToChannel(ctx context.Context, prompt string, ch chan StreamEventMsg) {
	defer close(ch)

	req := api.ChatRequest{
		Message: prompt,
		Model:   m.CurrentModel,
		UseRAG:  m.Config.RAGEnabled,
	}

	if m.ConversationID > 0 {
		req.ConversationID = strconv.Itoa(m.ConversationID)
	}

	err := m.APIClient.ChatStream(ctx, req, func(eventType api.EventType, data interface{}) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case ch <- StreamEventMsg{EventType: eventType, Data: data, Channel: ch}:
			return nil
		}
	})

	if err != nil && ctx.Err() == nil {
		ch <- StreamEventMsg{Err: err, Channel: ch}
	}
}
