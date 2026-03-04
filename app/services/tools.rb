module Tools
  def self.registry
    @registry ||= {
      web_search: Tools::WebSearch,
      news_search: Tools::NewsSearch,
      weather_search: Tools::WeatherSearch,
      recall_memories: Tools::RecallMemories
    }.freeze
  end

  def self.fetch(name)
    registry.fetch(name.to_sym) { raise ArgumentError, "Tool '#{name}' not found." }
  end

  def self.schema
    registry.values.map do |tool_class|
      {
        type: "function",
        function: tool_class.schema
      }
    end
  end

  def self.available_tool_names
    registry.keys.map(&:to_s)
  end
end
