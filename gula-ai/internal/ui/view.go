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

	// Build the main layout
	var sections []string

	// Title bar
	sections = append(sections, m.renderTitleBar())

	// Main content area (chat + tools)
	sections = append(sections, m.renderMainContent())

	// Input area
	sections = append(sections, m.renderInputArea())

	// Status bar
	sections = append(sections, m.renderStatusBar())

	// Join all sections vertically
	view := lipgloss.JoinVertical(lipgloss.Left, sections...)

	// Overlay dialog if active
	if m.DialogActive {
		view = m.overlayDialog(view)
	}

	// Overlay help if active
	if m.ShowHelp {
		view = m.overlayHelp(view)
	}

	return view
}

func (m Model) renderTitleBar() string {
	title := m.Styles.Title.Render(" gula ai ")
	subtitle := m.Styles.Subtitle.Render(" - AI Agent TUI")

	titleBar := lipgloss.JoinHorizontal(lipgloss.Center, title, subtitle)

	// Pad to full width
	return lipgloss.NewStyle().
		Width(m.Width).
		Background(ColorBgLight).
		Render(titleBar)
}

func (m Model) renderMainContent() string {
	// Calculate available height
	availableHeight := m.Height - 6 // title + input + status + borders

	if m.ShowToolsPanel {
		// Two-column layout
		toolsWidth := 25
		chatWidth := m.Width - toolsWidth - 3

		// Chat panel
		chatStyle := m.Styles.ChatPanel
		if m.FocusedPanel == FocusChat {
			chatStyle = m.Styles.ChatPanelActive
		}
		chatPanel := chatStyle.
			Width(chatWidth).
			Height(availableHeight).
			Render(m.ChatView.View())

		// Tools panel
		toolsStyle := m.Styles.ToolsPanel
		if m.FocusedPanel == FocusTools {
			toolsStyle = m.Styles.ToolsPanelActive
		}
		toolsHeader := m.Styles.Title.Render("Tools")
		toolsContent := lipgloss.JoinVertical(lipgloss.Left, toolsHeader, "", m.ToolView.View())
		toolsPanel := toolsStyle.
			Width(toolsWidth).
			Height(availableHeight).
			Render(toolsContent)

		return lipgloss.JoinHorizontal(lipgloss.Top, chatPanel, toolsPanel)
	}

	// Single column layout
	chatStyle := m.Styles.ChatPanel
	if m.FocusedPanel == FocusChat {
		chatStyle = m.Styles.ChatPanelActive
	}
	return chatStyle.
		Width(m.Width - 2).
		Height(availableHeight).
		Render(m.ChatView.View())
}

func (m Model) renderInputArea() string {
	inputStyle := m.Styles.InputArea
	if m.FocusedPanel == FocusInput {
		inputStyle = inputStyle.BorderForeground(ColorBorderActive)
	}

	// Show state indicator
	var prefix string
	switch m.AppState {
	case StateThinking:
		prefix = m.Styles.Thinking.Render(m.Spinner.View() + " Thinking... ")
	case StateStreaming:
		prefix = m.Styles.Thinking.Render(m.Spinner.View() + " Streaming... ")
	case StateWaitingApproval:
		prefix = m.Styles.Thinking.Render("⚠ Waiting for approval... ")
	default:
		prefix = ""
	}

	inputContent := prefix + m.Input.View()

	return inputStyle.
		Width(m.Width - 2).
		Render(inputContent)
}

func (m Model) renderStatusBar() string {
	// Model
	modelStr := m.Styles.StatusModel.Render(m.CurrentModel)

	// Session ID (truncated)
	sessionStr := ""
	if m.Stats.ConversationID != "" {
		shortID := m.Stats.ConversationID
		if len(shortID) > 8 {
			shortID = shortID[:8]
		}
		sessionStr = m.Styles.StatusSession.Render("#" + shortID)
	}

	// Cost
	costStr := m.Styles.StatusCost.Render(fmt.Sprintf("$%.4f", m.Stats.TotalCost))

	// Tokens
	tokensStr := m.Styles.StatusTokens.Render(fmt.Sprintf("%d tokens", m.Stats.TotalTokens))

	// RAG indicator
	ragStr := ""
	if m.Config.RAGEnabled {
		ragStr = m.Styles.StatusRAG.Render("● RAG")
	}

	// Help hint
	helpStr := m.Styles.Help.Render("Ctrl+? help")

	// Build status bar
	left := lipgloss.JoinHorizontal(lipgloss.Center, modelStr, sessionStr, costStr, tokensStr, ragStr)
	right := helpStr

	// Calculate padding
	padding := m.Width - lipgloss.Width(left) - lipgloss.Width(right) - 2
	if padding < 0 {
		padding = 0
	}
	spacer := strings.Repeat(" ", padding)

	return m.Styles.StatusBar.
		Width(m.Width).
		Render(left + spacer + right)
}

func (m Model) overlayDialog(background string) string {
	// Create dialog content
	title := m.Styles.DialogTitle.Render(m.DialogTitle)
	content := m.DialogContent

	// Buttons
	yesBtn := m.Styles.DialogButton.Render("[Y]es")
	noBtn := m.Styles.DialogButton.Render("[N]o")
	buttons := lipgloss.JoinHorizontal(lipgloss.Center, yesBtn, noBtn)

	dialogContent := lipgloss.JoinVertical(lipgloss.Center, title, "", content, "", buttons)

	dialog := m.Styles.Dialog.
		Width(50).
		Render(dialogContent)

	// Center the dialog over the background
	return placeOverlay(m.Width, m.Height, dialog, background)
}

func (m Model) overlayHelp(background string) string {
	// Create help content
	title := m.Styles.DialogTitle.Render("Keyboard Shortcuts")

	var lines []string
	lines = append(lines, "Navigation:")
	lines = append(lines, "  ↑/k, ↓/j    Scroll up/down")
	lines = append(lines, "  Tab         Switch panel")
	lines = append(lines, "")
	lines = append(lines, "Actions:")
	lines = append(lines, "  Enter       Send message")
	lines = append(lines, "  Ctrl+N      New conversation")
	lines = append(lines, "  Ctrl+T      Toggle tools panel")
	lines = append(lines, "  Ctrl+S      List sessions")
	lines = append(lines, "  Ctrl+M      Change model")
	lines = append(lines, "")
	lines = append(lines, "Other:")
	lines = append(lines, "  Esc         Cancel/unfocus")
	lines = append(lines, "  Ctrl+C      Quit")
	lines = append(lines, "  ?           Toggle this help")

	content := strings.Join(lines, "\n")

	closeBtn := m.Styles.DialogButton.Render("Press ? or Esc to close")

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, "", content, "", closeBtn)

	dialog := m.Styles.Dialog.
		Width(45).
		Render(dialogContent)

	return placeOverlay(m.Width, m.Height, dialog, background)
}

// placeOverlay places a dialog in the center of the background
func placeOverlay(width, height int, overlay, background string) string {
	// Split background into lines
	bgLines := strings.Split(background, "\n")
	overlayLines := strings.Split(overlay, "\n")

	// Calculate position
	overlayWidth := lipgloss.Width(overlay)
	overlayHeight := len(overlayLines)

	startX := (width - overlayWidth) / 2
	startY := (height - overlayHeight) / 2

	if startX < 0 {
		startX = 0
	}
	if startY < 0 {
		startY = 0
	}

	// Overlay the dialog
	for i, line := range overlayLines {
		bgY := startY + i
		if bgY < len(bgLines) {
			// Replace part of the background line with the overlay
			bgLine := bgLines[bgY]
			bgRunes := []rune(bgLine)

			// Ensure bgLine is long enough
			for len(bgRunes) < startX+len([]rune(line)) {
				bgRunes = append(bgRunes, ' ')
			}

			// Copy overlay line into background
			overlayRunes := []rune(line)
			for j, r := range overlayRunes {
				if startX+j < len(bgRunes) {
					bgRunes[startX+j] = r
				}
			}

			bgLines[bgY] = string(bgRunes)
		}
	}

	return strings.Join(bgLines, "\n")
}
