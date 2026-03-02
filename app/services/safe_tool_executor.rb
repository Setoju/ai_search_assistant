class SafeToolExecutor
  TOOL_TIMEOUT = 15
  MAX_OUTPUT_SIZE = 10_000
  MAX_TOOL_CALLS_PER_REQUEST = 8

  class TooManyToolCallsError < StandardError; end

  attr_reader :call_count

  def initialize
    @call_count = 0
  end

  def execute(tool_name, arguments)
    @call_count += 1

    if @call_count > MAX_TOOL_CALLS_PER_REQUEST
      raise TooManyToolCallsError, "Maximum tool calls (#{MAX_TOOL_CALLS_PER_REQUEST}) exceeded."
    end

    tool_class = Tools.fetch(tool_name)
    safe_args = sanitize_arguments(arguments)

    result = Timeout.timeout(TOOL_TIMEOUT) { tool_class.call(safe_args) }

    truncate_output(result)
  rescue Timeout::Error
    { error: "Tool '#{tool_name}' timed out." }
  rescue ArgumentError => e
    { error: "Invalid input for '#{tool_name}': #{e.message}" }
  rescue TooManyToolCallsError => e
    { error: e.message }
  rescue => e
    Rails.logger.error("[SafeToolExecutor] #{tool_name} failed: #{e.class} - #{e.message}")
    { error: "Tool '#{tool_name}' encountered an error." }
  end

  private

  def sanitize_arguments(arguments)
    case arguments
    when Hash
      arguments.transform_keys { |k| k.to_s.gsub(/[^a-zA-Z0-9_]/, "").to_sym }
    when String
      JSON.parse(arguments, symbolize_names: true) rescue {}
    else
      {}
    end
  end

  def truncate_output(result)
    json = result.to_json
    return result if json.length <= MAX_OUTPUT_SIZE

    if result.is_a?(Hash)
      result.each do |key, value|
        if value.is_a?(String) && value.length > 500
          result[key] = value.slice(0, 500) + "... [truncated]"
        elsif value.is_a?(Array)
          result[key] = value.first(3)
        end
        break if result.to_json.length <= MAX_OUTPUT_SIZE
      end
    end
    result
  end
end
