package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is the API client for the agent microservice
type Client struct {
	BaseURL    string
	APIKey     string
	HTTPClient *http.Client
}

// NewClient creates a new API client
func NewClient(baseURL, apiKey string) *Client {
	return &Client{
		BaseURL: baseURL,
		APIKey:  apiKey,
		HTTPClient: &http.Client{
			Timeout: 0, // No timeout for streaming
		},
	}
}

// ChatRequest represents a chat request
type ChatRequest struct {
	Message        string                 `json:"message"`
	ConversationID string                 `json:"conversation_id,omitempty"`
	Model          string                 `json:"model,omitempty"`
	Context        map[string]interface{} `json:"context,omitempty"`
	UseRAG         bool                   `json:"use_rag,omitempty"`
	ToolResults    []ToolResult           `json:"tool_results,omitempty"`
}

// StreamCallback is called for each SSE event
type StreamCallback func(eventType EventType, data interface{}) error

// ChatStream sends a chat request and streams the response
func (c *Client) ChatStream(ctx context.Context, req ChatRequest, callback StreamCallback) error {
	// Build request body
	body, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request
	url := c.BaseURL + "/api/v1/agent/chat/hybrid"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")
	if c.APIKey != "" {
		httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	// Send request
	resp, err := c.HTTPClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Check status code
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	// Parse SSE events
	reader := NewSSEReader(resp.Body)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		event, err := reader.ReadEvent()
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return fmt.Errorf("failed to read event: %w", err)
		}

		// Parse and dispatch event
		if err := c.dispatchEvent(event, callback); err != nil {
			return err
		}
	}
}

func (c *Client) dispatchEvent(event *SSEEvent, callback StreamCallback) error {
	eventType := EventType(event.Event)

	switch eventType {
	case EventStarted:
		data, err := ParseStartedEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventThinking:
		return callback(eventType, &ThinkingEvent{})

	case EventText:
		data, err := ParseTextEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventToolRequests:
		data, err := ParseToolRequestsEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventRAGSearch:
		data, err := ParseRAGSearchEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventRAGContext:
		data, err := ParseRAGContextEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventComplete:
		data, err := ParseCompleteEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventError:
		data, err := ParseErrorEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventRateLimited:
		data, err := ParseRateLimitedEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	case EventCostWarning:
		data, err := ParseCostWarningEvent(event.Data)
		if err != nil {
			return err
		}
		return callback(eventType, data)

	default:
		// Unknown event, ignore
		return nil
	}
}

// SendToolResults sends tool results back to the API
func (c *Client) SendToolResults(ctx context.Context, conversationID string, results []ToolResult) error {
	req := ChatRequest{
		ConversationID: conversationID,
		ToolResults:    results,
	}

	body, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}

	url := c.BaseURL + "/api/v1/agent/chat/tool-results"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	resp, err := c.HTTPClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	return nil
}

// HealthCheck checks if the API is available
func (c *Client) HealthCheck(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	url := c.BaseURL + "/health"
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("health check failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health check returned status %d", resp.StatusCode)
	}

	return nil
}
