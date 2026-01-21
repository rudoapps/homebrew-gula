package api

// EventType represents the type of SSE event
type EventType string

const (
	EventStarted      EventType = "started"
	EventThinking     EventType = "thinking"
	EventText         EventType = "text"
	EventToolRequests EventType = "tool_requests"
	EventToolResults  EventType = "tool_results"
	EventRAGSearch    EventType = "rag_search"
	EventRAGContext   EventType = "rag_context"
	EventComplete     EventType = "complete"
	EventError        EventType = "error"
	EventRateLimited  EventType = "rate_limited"
	EventCostWarning  EventType = "cost_warning"
)

// Event represents a generic SSE event
type Event struct {
	Type EventType   `json:"event"`
	Data interface{} `json:"data"`
}

// StartedEvent is sent when the conversation starts
type StartedEvent struct {
	ConversationID string `json:"conversation_id"`
	Model          string `json:"model"`
	Timestamp      string `json:"timestamp"`
}

// ThinkingEvent is sent when the agent is thinking
type ThinkingEvent struct {
	Message string `json:"message,omitempty"`
}

// TextEvent is sent when the agent generates text
type TextEvent struct {
	Content string `json:"content"`
}

// ToolRequest represents a tool execution request
type ToolRequest struct {
	ID   string                 `json:"id"`
	Name string                 `json:"name"`
	Args map[string]interface{} `json:"args"`
}

// ToolRequestsEvent is sent when tools need to be executed
type ToolRequestsEvent struct {
	Tools []ToolRequest `json:"tools"`
}

// ToolResult represents the result of a tool execution
type ToolResult struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Result string `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

// ToolResultsEvent is sent with tool execution results
type ToolResultsEvent struct {
	Results []ToolResult `json:"results"`
}

// RAGSearchEvent is sent when RAG search begins
type RAGSearchEvent struct {
	Query string `json:"query"`
}

// RAGChunk represents a code chunk from RAG
type RAGChunk struct {
	File    string  `json:"file"`
	Content string  `json:"content"`
	Score   float64 `json:"score"`
}

// RAGContextEvent is sent with RAG search results
type RAGContextEvent struct {
	Chunks []RAGChunk `json:"chunks"`
}

// CompleteEvent is sent when the response is complete
type CompleteEvent struct {
	TotalTokens   int     `json:"total_tokens"`
	InputTokens   int     `json:"input_tokens"`
	OutputTokens  int     `json:"output_tokens"`
	TotalCost     float64 `json:"total_cost"`
	StopReason    string  `json:"stop_reason,omitempty"`
}

// ErrorEvent is sent when an error occurs
type ErrorEvent struct {
	Error   string `json:"error"`
	Code    string `json:"code,omitempty"`
	Details string `json:"details,omitempty"`
}

// RateLimitedEvent is sent when rate limited
type RateLimitedEvent struct {
	RetryAfter int    `json:"retry_after"`
	Message    string `json:"message"`
}

// CostWarningEvent is sent when approaching cost limits
type CostWarningEvent struct {
	Message      string  `json:"message"`
	CurrentCost  float64 `json:"current_cost"`
	CostLimit    float64 `json:"cost_limit,omitempty"`
}
