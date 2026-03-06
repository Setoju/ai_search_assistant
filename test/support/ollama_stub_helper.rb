# Shared helpers for stubbing Ollama LLM HTTP calls in service tests.
module OllamaStubHelper
  # Build the parsed JSON hash that Orchestrator#call_llm returns when the model
  # responds with plain text (no tool calls).
  def ollama_text_response(content)
    {
      "model" => "llama3.2",
      "message" => { "role" => "assistant", "content" => content, "tool_calls" => nil },
      "done" => true
    }
  end

  # Build the parsed JSON hash that Orchestrator#call_llm returns when the model
  # wants to invoke one or more tools via the structured tool_calls API.
  def ollama_tool_call_response(tool_name, arguments)
    {
      "model" => "llama3.2",
      "message" => {
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          { "function" => { "name" => tool_name, "arguments" => arguments } }
        ]
      },
      "done" => true
    }
  end

  # Stub Memory::Extractor.call_llm (private class method) to return +content+
  # (a plain JSON string, as the real method does) for the duration of the block.
  def stub_extractor_llm(content, &block)
    Memory::Extractor.stub(:call_llm, content, &block)
  end

  # Stub Memory::ConflictResolver.call_llm to return +content+ for the block.
  def stub_conflict_resolver_llm(content, &block)
    Memory::ConflictResolver.stub(:call_llm, content, &block)
  end
end
