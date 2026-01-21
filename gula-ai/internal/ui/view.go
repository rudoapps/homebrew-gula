package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// View implements tea.Model
func (m Model) View() string {
	if m.Width == 0 || m.Height == 0 {
		return "Loading..."
	}

	var sections []string

	// Chat area
	sections = append(sections, m.renderChatArea())

	// Input area
	sections = append(sections, m.renderInputArea())

	// Status bar
	sections = append(sections, m.renderStatusBar())

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

func (m Model) renderChatArea() string {
	return m.ChatView.View()
}

func (m Model) renderInputArea() string {
	var prefix string
	switch m.AppState {
	case StateConnecting:
		prefix = m.Styles.Spinner.Render(m.Spinner.View()) + " "
	case StateStreaming:
		prefix = m.Styles.Spinner.Render(m.Spinner.View()) + " "
	default:
		prefix = ""
	}

	inputContent := prefix + m.Input.View()
	return inputContent
}

func (m Model) renderStatusBar() string {
	// Model
	modelStr := m.Styles.Dim.Render(m.CurrentModel)

	// Session
	sessionStr := ""
	if m.ConversationID > 0 {
		sessionStr = m.Styles.Dim.Render(fmt.Sprintf(" · #%d", m.ConversationID))
	}

	// Cost
	costStr := ""
	if m.TotalCost > 0 {
		costStr = m.Styles.Dim.Render(fmt.Sprintf(" · $%.4f", m.TotalCost))
	}

	// Tokens
	tokensStr := ""
	if m.TotalTokens > 0 {
		tokensStr = m.Styles.Dim.Render(fmt.Sprintf(" · %d tokens", m.TotalTokens))
	}

	// Help hint
	helpStr := m.Styles.Dim.Render(" · Ctrl+C quit")

	// Build status bar
	left := modelStr + sessionStr + costStr + tokensStr
	right := helpStr

	// Calculate padding
	padding := m.Width - lipgloss.Width(left) - lipgloss.Width(right)
	if padding < 0 {
		padding = 0
	}
	spacer := strings.Repeat(" ", padding)

	return left + spacer + right
}
