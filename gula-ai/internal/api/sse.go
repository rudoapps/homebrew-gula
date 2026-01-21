package api

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strings"
)

// SSEEvent represents a parsed SSE event
type SSEEvent struct {
	Event string
	Data  string
	ID    string
	Retry int
}

// SSEReader reads and parses SSE events from a stream
type SSEReader struct {
	reader *bufio.Reader
}

// NewSSEReader creates a new SSE reader
func NewSSEReader(r io.Reader) *SSEReader {
	return &SSEReader{
		reader: bufio.NewReader(r),
	}
}

// ReadEvent reads the next SSE event from the stream
func (r *SSEReader) ReadEvent() (*SSEEvent, error) {
	event := &SSEEvent{}
	var dataLines []string

	for {
		line, err := r.reader.ReadString('\n')
		if err != nil {
			if err == io.EOF && len(dataLines) > 0 {
				// Return the last event if we have data
				event.Data = strings.Join(dataLines, "\n")
				return event, nil
			}
			return nil, err
		}

		line = strings.TrimSuffix(line, "\n")
		line = strings.TrimSuffix(line, "\r")

		// Empty line signals end of event
		if line == "" {
			if event.Event != "" || len(dataLines) > 0 {
				event.Data = strings.Join(dataLines, "\n")
				return event, nil
			}
			continue
		}

		// Parse field
		if strings.HasPrefix(line, ":") {
			// Comment, ignore
			continue
		}

		var field, value string
		colonIdx := strings.Index(line, ":")
		if colonIdx == -1 {
			field = line
			value = ""
		} else {
			field = line[:colonIdx]
			value = line[colonIdx+1:]
			// Remove leading space from value if present
			if strings.HasPrefix(value, " ") {
				value = value[1:]
			}
		}

		switch field {
		case "event":
			event.Event = value
		case "data":
			dataLines = append(dataLines, value)
		case "id":
			event.ID = value
		case "retry":
			// Parse retry value (not commonly used)
		}
	}
}

// ParseStartedEvent parses a started event
func ParseStartedEvent(data string) (*StartedEvent, error) {
	var event StartedEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse started event: %w", err)
	}
	return &event, nil
}

// ParseTextEvent parses a text event
func ParseTextEvent(data string) (*TextEvent, error) {
	var event TextEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse text event: %w", err)
	}
	return &event, nil
}

// ParseToolRequestsEvent parses a tool_requests event
func ParseToolRequestsEvent(data string) (*ToolRequestsEvent, error) {
	var event ToolRequestsEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse tool_requests event: %w", err)
	}
	return &event, nil
}

// ParseRAGSearchEvent parses a rag_search event
func ParseRAGSearchEvent(data string) (*RAGSearchEvent, error) {
	var event RAGSearchEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse rag_search event: %w", err)
	}
	return &event, nil
}

// ParseRAGContextEvent parses a rag_context event
func ParseRAGContextEvent(data string) (*RAGContextEvent, error) {
	var event RAGContextEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse rag_context event: %w", err)
	}
	return &event, nil
}

// ParseCompleteEvent parses a complete event
func ParseCompleteEvent(data string) (*CompleteEvent, error) {
	var event CompleteEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse complete event: %w", err)
	}
	return &event, nil
}

// ParseErrorEvent parses an error event
func ParseErrorEvent(data string) (*ErrorEvent, error) {
	var event ErrorEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse error event: %w", err)
	}
	return &event, nil
}

// ParseRateLimitedEvent parses a rate_limited event
func ParseRateLimitedEvent(data string) (*RateLimitedEvent, error) {
	var event RateLimitedEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse rate_limited event: %w", err)
	}
	return &event, nil
}

// ParseCostWarningEvent parses a cost_warning event
func ParseCostWarningEvent(data string) (*CostWarningEvent, error) {
	var event CostWarningEvent
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return nil, fmt.Errorf("failed to parse cost_warning event: %w", err)
	}
	return &event, nil
}
