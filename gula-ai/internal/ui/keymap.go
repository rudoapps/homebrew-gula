package ui

import (
	"github.com/charmbracelet/bubbles/key"
)

// KeyMap defines all keyboard shortcuts
type KeyMap struct {
	// Actions
	Send            key.Binding
	Cancel          key.Binding
	Quit            key.Binding
	NewConversation key.Binding
	Help            key.Binding
}

// DefaultKeyMap returns the default key bindings
func DefaultKeyMap() KeyMap {
	return KeyMap{
		Send: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("Enter", "send message"),
		),
		Cancel: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("Esc", "cancel"),
		),
		Quit: key.NewBinding(
			key.WithKeys("ctrl+c"),
			key.WithHelp("Ctrl+C", "quit"),
		),
		NewConversation: key.NewBinding(
			key.WithKeys("ctrl+n"),
			key.WithHelp("Ctrl+N", "new conversation"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "show help"),
		),
	}
}

// ShortHelp returns the short help for the key bindings
func (k KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Send,
		k.NewConversation,
		k.Quit,
	}
}

// FullHelp returns the full help for the key bindings
func (k KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Send, k.Cancel, k.Quit},
		{k.NewConversation, k.Help},
	}
}
