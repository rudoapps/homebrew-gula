package ui

import (
	"github.com/charmbracelet/bubbles/key"
)

// KeyMap defines all keyboard shortcuts
type KeyMap struct {
	// Navigation
	Up        key.Binding
	Down      key.Binding
	PageUp    key.Binding
	PageDown  key.Binding
	Home      key.Binding
	End       key.Binding
	Tab       key.Binding

	// Actions
	Send      key.Binding
	NewLine   key.Binding
	Cancel    key.Binding
	Quit      key.Binding

	// Panels
	ToggleTools key.Binding
	FocusChat   key.Binding
	FocusTools  key.Binding

	// Sessions
	NewConversation key.Binding
	ListSessions    key.Binding
	ChangeModel     key.Binding

	// Help
	Help key.Binding
}

// DefaultKeyMap returns the default key bindings
func DefaultKeyMap() KeyMap {
	return KeyMap{
		// Navigation
		Up: key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "scroll up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "scroll down"),
		),
		PageUp: key.NewBinding(
			key.WithKeys("pgup", "ctrl+u"),
			key.WithHelp("PgUp/Ctrl+U", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown", "ctrl+d"),
			key.WithHelp("PgDn/Ctrl+D", "page down"),
		),
		Home: key.NewBinding(
			key.WithKeys("home", "g"),
			key.WithHelp("Home/g", "go to top"),
		),
		End: key.NewBinding(
			key.WithKeys("end", "G"),
			key.WithHelp("End/G", "go to bottom"),
		),
		Tab: key.NewBinding(
			key.WithKeys("tab"),
			key.WithHelp("Tab", "switch panel"),
		),

		// Actions
		Send: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("Enter", "send message"),
		),
		NewLine: key.NewBinding(
			key.WithKeys("shift+enter", "ctrl+j"),
			key.WithHelp("Shift+Enter", "new line"),
		),
		Cancel: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("Esc", "cancel"),
		),
		Quit: key.NewBinding(
			key.WithKeys("ctrl+c"),
			key.WithHelp("Ctrl+C", "quit"),
		),

		// Panels
		ToggleTools: key.NewBinding(
			key.WithKeys("ctrl+t"),
			key.WithHelp("Ctrl+T", "toggle tools panel"),
		),
		FocusChat: key.NewBinding(
			key.WithKeys("ctrl+1"),
			key.WithHelp("Ctrl+1", "focus chat"),
		),
		FocusTools: key.NewBinding(
			key.WithKeys("ctrl+2"),
			key.WithHelp("Ctrl+2", "focus tools"),
		),

		// Sessions
		NewConversation: key.NewBinding(
			key.WithKeys("ctrl+n"),
			key.WithHelp("Ctrl+N", "new conversation"),
		),
		ListSessions: key.NewBinding(
			key.WithKeys("ctrl+s"),
			key.WithHelp("Ctrl+S", "list sessions"),
		),
		ChangeModel: key.NewBinding(
			key.WithKeys("ctrl+m"),
			key.WithHelp("Ctrl+M", "change model"),
		),

		// Help
		Help: key.NewBinding(
			key.WithKeys("?", "ctrl+?"),
			key.WithHelp("?", "show help"),
		),
	}
}

// ShortHelp returns the short help for the key bindings
func (k KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Send,
		k.NewConversation,
		k.ToggleTools,
		k.Help,
		k.Quit,
	}
}

// FullHelp returns the full help for the key bindings
func (k KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.PageUp, k.PageDown, k.Home, k.End},
		{k.Send, k.NewLine, k.Cancel, k.Quit},
		{k.Tab, k.ToggleTools, k.FocusChat, k.FocusTools},
		{k.NewConversation, k.ListSessions, k.ChangeModel},
	}
}
